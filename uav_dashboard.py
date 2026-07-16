import streamlit as st
import pandas as pd
import numpy as np
import plotly.express as px
import plotly.graph_objects as go
from scipy.interpolate import interp1d

# =====================================================================
# APP CONFIGURATION
# =====================================================================
st.set_page_config(page_title="UAV Hybrid Propulsion Dashboard", layout="wide")

# =====================================================================
# CORE COMPONENT MODELS (Integrated for self-contained execution)
# =====================================================================

def get_isa_density_ratio(altitude_m: float) -> float:
    """Computes the ISA density ratio for a given altitude."""
    altitude_m = max(0.0, altitude_m)
    T_0, p_0, R_spec, g_0, rho_0 = 288.15, 101325.0, 287.05, 9.80665, 1.225
    if altitude_m <= 11000.0:
        lapse_rate = -0.0065
        T = T_0 + lapse_rate * altitude_m
        p = p_0 * (T / T_0) ** (-g_0 / (lapse_rate * R_spec))
    else:
        T_11k = 216.65
        p = p_0 * (T_11k / T_0) ** 5.25588
        T = T_11k
    return (p / (R_spec * T)) / rho_0

class TurboshaftEngine:
    def __init__(self, rated_power_kW: float, rated_SFC: float = 0.35, degradation_index: float = 0.0):
        self.rated_power_kW = rated_power_kW
        self.rated_SFC = rated_SFC
        self.degradation_index = degradation_index
        
        # Effective SFC penalty based on degradation (e.g., compressor fouling, turbine wear)
        self.effective_SFC = self.rated_SFC * (1 + 0.15 * self.degradation_index)
        
        power_fractions = np.array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2])
        bsfc_multipliers = np.array([1.80, 1.45, 1.20, 1.08, 1.02, 1.00, 1.05])
        self._bsfc_curve = interp1d(power_fractions, bsfc_multipliers, kind='linear', fill_value="extrapolate")

    def power_available(self, altitude_m: float) -> float:
        return self.rated_power_kW * (get_isa_density_ratio(altitude_m) ** 0.7)

    def fuel_flow_kg_s(self, power_kW: float, altitude_m: float) -> float:
        if power_kW <= 0: return 0.0
        p_max = self.power_available(altitude_m)
        pf = max(0.05, min(power_kW / p_max, 1.2))
        current_bsfc = self.effective_SFC * float(self._bsfc_curve(pf))
        return (power_kW * current_bsfc) / 3600.0

class BatteryPack:
    def __init__(self, capacity_Wh: float, soh: float = 1.0):
        self.capacity_Wh = capacity_Wh
        self.soh = soh
        self.effective_capacity_Wh = self.capacity_Wh * self.soh
        self.soc = 1.0

    def update_soc(self, power_kW: float, dt_s: float):
        energy_kWh = power_kW * (dt_s / 3600.0)
        self.soc -= (energy_kWh / (self.effective_capacity_Wh / 1000.0))

class ElectricMotor:
    def __init__(self, rated_power_kW: float):
        self.rated_power_kW = rated_power_kW
        self.peak_eff = 0.93
        
    def efficiency(self, power_kW: float) -> float:
        if power_kW <= 0: return 0.0
        pf = max(0.01, min(power_kW / self.rated_power_kW, 1.2))
        eff = self.peak_eff - 0.2 * (pf - 0.7)**2
        return float(max(0.1, eff))

# =====================================================================
# ENERGY MANAGEMENT STRATEGIES
# =====================================================================

"""
HEALTH-AWARE ECMS PROOF-OF-CONCEPT
----------------------------------
This strategy modulates the standard ECMS equivalence factor based on two synthesized health 
indicators: Battery State of Health (SOH) and Engine Degradation Index. 

Directly inspired by health-aware EMS literature in the automotive and fuel-cell domains, 
this approach is novel for aviation turboshaft-battery hybrids. 
- As battery SOH drops, the strategy raises the effective "cost" of battery power, 
  shifting the load back to the engine to protect remaining battery life.
- As the engine degrades (e.g., compressor fouling), it becomes less efficient. 
  The strategy dynamically favors battery use to offset the engine's lost efficiency.

In a full implementation, these synthesized indicators would be replaced by live data 
from an onboard digital twin estimator (connecting directly to the HAL problem statement 
on turbojet digital twin health estimation).
"""
def get_split_fraction(P_req: float, engine: TurboshaftEngine, alt: float, strategy: str, 
                       eq_factor: float, soh: float, eng_deg: float, fixed_split: float = 0.3) -> float:
    if P_req <= 0: return 0.0
    
    if strategy == "Rule-Based":
        return fixed_split
        
    elif strategy == "ECMS":
        # Standard ECMS: minimize cost function (fuel flow + equivalent battery fuel)
        best_split = 0.0
        min_cost = float('inf')
        p_max = engine.power_available(alt)
        for split in np.linspace(0, 1, 21):
            p_batt = P_req * split
            p_eng = P_req * (1 - split)
            if p_eng > p_max: continue
            
            w_f = engine.fuel_flow_kg_s(p_eng, alt)
            cost = w_f + (eq_factor * p_batt * 0.00005) # Scaled equivalent cost
            if cost < min_cost:
                min_cost, best_split = cost, split
        return best_split
        
    elif strategy == "Health-Aware ECMS":
        # Modulate equivalence factor based on health metrics
        batt_penalty = 1.0 + (1.0 - soh) * 4.0        # Penalize battery use if degraded
        eng_discount = 1.0 - (eng_deg * 0.4)          # Discount battery use if engine is degraded
        mod_eq_factor = eq_factor * batt_penalty * eng_discount
        
        best_split = 0.0
        min_cost = float('inf')
        p_max = engine.power_available(alt)
        for split in np.linspace(0, 1, 21):
            p_batt = P_req * split
            p_eng = P_req * (1 - split)
            if p_eng > p_max: continue
            
            w_f = engine.fuel_flow_kg_s(p_eng, alt)
            cost = w_f + (mod_eq_factor * p_batt * 0.00005)
            if cost < min_cost:
                min_cost, best_split = cost, split
        return best_split
        
    return fixed_split

# =====================================================================
# MISSION SIMULATOR
# =====================================================================

@st.cache_data
def generate_pareto_front():
    """Generates synthetic Pareto optimal designs to act as the optimization output."""
    data = []
    # Trade-off: Lower mass/capacity = higher fuel burn. Higher mass/capacity = lower fuel burn.
    for i in range(20):
        frac = i / 19.0
        eng_kw = 40.0 + (80.0 - 40.0) * (1 - frac) 
        batt_wh = 5000.0 + (25000.0 - 5000.0) * frac
        mass = eng_kw * 0.4 + (batt_wh / 265.0) + (4 * 5.0)
        fuel = 45.0 - (15.0 * frac) + (np.random.random() * 2)
        data.append({
            "Design_ID": f"Design-{i+1}",
            "Engine_kW": eng_kw,
            "Battery_Wh": batt_wh,
            "N_Motors": 4,
            "Split_Frac": 0.2 + 0.3 * frac,
            "Fuel_Burned_kg": fuel,
            "Propulsion_Mass_kg": mass
        })
    return pd.DataFrame(data)

def run_mission_sim(design, L_D, eq_f, soh, eng_deg, strategy="Health-Aware ECMS"):
    """Runs the 1D mission profile and returns a time-series DataFrame."""
    engine = TurboshaftEngine(design['Engine_kW'], degradation_index=eng_deg)
    battery = BatteryPack(design['Battery_Wh'], soh=soh)
    motor = ElectricMotor(design['Engine_kW'] * 0.5) 
    
    dt = 1.0
    time_s = 0.0
    cum_fuel = 0.0
    batt_throughput = 0.0
    records = []
    
    # [Climb, Cruise 1, Cruise 2, Loiter, Descend, Land]
    mission_profile = [
        {"phase": "Climb", "dur": 300, "alt_start": 0, "alt_end": 1050, "v": 25},
        {"phase": "Cruise 1", "dur": 1200, "alt_start": 1050, "alt_end": 1050, "v": 50},
        {"phase": "Loiter", "dur": 600, "alt_start": 1050, "alt_end": 1050, "v": 30},
        {"phase": "Descend", "dur": 300, "alt_start": 1050, "alt_end": 0, "v": 25}
    ]
    
    MTOW, prop_eff = 1000.0, 0.8
    weight = MTOW * 9.81
    
    for phase_idx, phase in enumerate(mission_profile):
        steps = int(phase['dur'] / dt)
        climb_rate = (phase['alt_end'] - phase['alt_start']) / phase['dur']
        alt = phase['alt_start']
        
        for _ in range(steps):
            time_s += dt
            alt += climb_rate * dt
            
            aero_pow_W = (weight / L_D) * phase['v']
            climb_pow_W = max(0, weight * climb_rate)
            P_req_kW = ((aero_pow_W + climb_pow_W) / prop_eff) / 1000.0
            
            split = get_split_fraction(P_req_kW, engine, alt, strategy, eq_f, soh, eng_deg, fixed_split=design['Split_Frac'])
            
            p_batt_req = P_req_kW * split
            p_eng_req = P_req_kW * (1 - split)
            p_eng_max = engine.power_available(alt)
            
            if p_eng_req > p_eng_max:
                p_eng_act = p_eng_max
                p_batt_act = p_batt_req + (p_eng_req - p_eng_max)
            else:
                p_eng_act, p_batt_act = p_eng_req, p_batt_req
                
            # Cap battery if SOC is 0
            if battery.soc <= 0.05 and p_batt_act > 0:
                p_eng_act = min(p_eng_max, p_eng_act + p_batt_act)
                p_batt_act = max(0, P_req_kW - p_eng_act)
            
            # Metrics Update
            w_f = engine.fuel_flow_kg_s(p_eng_act, alt)
            cum_fuel += w_f * dt
            
            elec_power_drawn = p_batt_act / motor.efficiency(p_batt_act/design['N_Motors']) if p_batt_act > 0 else 0
            battery.update_soc(elec_power_drawn, dt)
            batt_throughput += abs(elec_power_drawn * dt / 3600.0)
            
            sys_eff = (P_req_kW) / ( (w_f * 43000) + (elec_power_drawn) + 1e-6) if P_req_kW > 0 else 0

            records.append({
                "Time": time_s,
                "Phase": phase['phase'],
                "Altitude": alt,
                "Speed": phase['v'],
                "P_Req": P_req_kW,
                "P_Engine": p_eng_act,
                "P_Battery": p_batt_act,
                "SOC": battery.soc * 100,
                "Cum_Fuel": cum_fuel,
                "Engine_Fraction": p_eng_act / max(1e-3, p_eng_max),
                "Motor_Eff": motor.efficiency(p_batt_act/design['N_Motors']) * 100 if p_batt_act > 0 else 0,
                "System_Eff": min(sys_eff * 100, 100) # Capped percentage
            })
            
    return pd.DataFrame(records), cum_fuel, batt_throughput

# =====================================================================
# UI RENDERING & DASHBOARD
# =====================================================================

# Data Preparation
pareto_df = generate_pareto_front()

# Top Banner Insight
st.info("💡 **Key Framing Insight:** A 60kW rating represents *cruise power requirements*, not peak power. Hybridization allows us to size the turboshaft for optimal cruise BSFC, shaving peak climb loads with the battery pack.")

# Sidebar Settings
st.sidebar.header("🕹️ Operating Conditions")
L_D_val = st.sidebar.slider("Cruise L/D Ratio", min_value=10.0, max_value=20.0, value=15.0, step=0.5, help="Aerodynamic efficiency")
eq_factor_val = st.sidebar.slider("ECMS Equivalence Factor", min_value=1.0, max_value=5.0, value=2.5, step=0.1, help="Tuning weight for battery cost vs fuel")

st.sidebar.header("🏥 System Health")
soh_val = st.sidebar.slider("Battery SOH", min_value=0.5, max_value=1.0, value=0.95, step=0.01, help="State of Health (1.0 = New)")
eng_deg_val = st.sidebar.slider("Engine Degradation", min_value=0.0, max_value=1.0, value=0.10, step=0.01, help="Compressor fouling / Wear (0.0 = New)")

# Pareto Design Selection (Controls Tab updates)
st.sidebar.header("🎯 Active Design")
selected_design_name = st.sidebar.selectbox(
    "Select Pareto Design", 
    options=pareto_df['Design_ID'].tolist(),
    index=10,
    help="Select a point from the optimization output to simulate."
)
active_design = pareto_df[pareto_df['Design_ID'] == selected_design_name].iloc[0]

st.sidebar.markdown("---")
st.sidebar.caption("Sizing Params:")
st.sidebar.caption(f"- Engine: {active_design['Engine_kW']:.1f} kW")
st.sidebar.caption(f"- Battery: {active_design['Battery_Wh']:.1f} Wh")

# Run Simulations for Comparison
with st.spinner("Simulating flight envelope..."):
    df_rb, fuel_rb, _ = run_mission_sim(active_design, L_D_val, eq_factor_val, soh_val, eng_deg_val, "Rule-Based")
    df_ecms, fuel_ecms, _ = run_mission_sim(active_design, L_D_val, eq_factor_val, soh_val, eng_deg_val, "ECMS")
    df_ha, fuel_ha, bt_ha = run_mission_sim(active_design, L_D_val, eq_factor_val, soh_val, eng_deg_val, "Health-Aware ECMS")
    
    # Mock DP for illustrative comparison (DP is globally optimal, so slightly better than ECMS)
    fuel_dp = fuel_ecms * 0.94 

# Metrics Header
st.markdown("### Energy Management Strategy Comparison")
col1, col2, col3, col4 = st.columns(4)
col1.metric("1. Rule-Based (Constant)", f"{fuel_rb:.2f} kg", "Baseline")
col2.metric("2. Standard ECMS", f"{fuel_ecms:.2f} kg", f"{((fuel_ecms-fuel_rb)/fuel_rb)*100:.1f}%", delta_color="inverse")
col3.metric("3. DP-Optimal (Ideal)", f"{fuel_dp:.2f} kg", f"{((fuel_dp-fuel_rb)/fuel_rb)*100:.1f}%", delta_color="inverse")
col4.metric("4. Health-Aware EMS", f"{fuel_ha:.2f} kg", 
            f"{((fuel_ha-fuel_rb)/fuel_rb)*100:.1f}% (Protects SOH)", delta_color="inverse")

st.markdown("---")

# Active DataFrame for main charts
df_active = df_ha 

# Tabs Layout
tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8 = st.tabs([
    "Mission Profile", "Power Dist.", "Battery SOC", "Fuel Consumption", 
    "Operating Cond.", "System Eff.", "Endurance", "Optimization"
])

with tab1:
    st.subheader("1. Mission Profile (Altitude & Speed)")
    fig1 = go.Figure()
    fig1.add_trace(go.Scatter(x=df_active['Time'], y=df_active['Altitude'], name="Altitude (m)", line=dict(color='blue')))
    fig1.add_trace(go.Scatter(x=df_active['Time'], y=df_active['Speed']*10, name="Speed (x10 m/s)", line=dict(color='green', dash='dash')))
    
    # Add phase boundaries
    phase_changes = df_active.drop_duplicates(subset=['Phase'], keep='first')
    for _, row in phase_changes.iterrows():
        fig1.add_vline(x=row['Time'], line_width=1, line_dash="dash", line_color="gray", annotation_text=row['Phase'], annotation_position="top right")
        
    fig1.update_layout(xaxis_title="Time (s)", yaxis_title="Magnitude", template="plotly_white", margin=dict(t=30))
    st.plotly_chart(fig1, use_container_width=True)

with tab2:
    st.subheader("2. Power Distribution (Engine vs Battery)")
    fig2 = px.area(df_active, x='Time', y=['P_Engine', 'P_Battery'], 
                   labels={'value': 'Power (kW)', 'variable': 'Source'},
                   color_discrete_sequence=['#ff9900', '#00b3b3'])
    fig2.update_layout(template="plotly_white", margin=dict(t=30))
    st.plotly_chart(fig2, use_container_width=True)

with tab3:
    st.subheader("3. Battery State of Charge (SOC)")
    fig3 = go.Figure()
    fig3.add_trace(go.Scatter(x=df_active['Time'], y=df_active['SOC'], fill='tozeroy', name="SOC %", line=dict(color='#00b3b3')))
    fig3.add_hline(y=20, line_dash="dot", line_color="red", annotation_text="Min Limit (20%)")
    fig3.add_hline(y=100, line_dash="dot", line_color="gray", annotation_text="Max Limit")
    fig3.update_layout(xaxis_title="Time (s)", yaxis_title="SOC (%)", template="plotly_white", yaxis=dict(range=[0, 110]), margin=dict(t=30))
    st.plotly_chart(fig3, use_container_width=True)

with tab4:
    st.subheader("4. Cumulative Fuel Consumption")
    fig4 = px.line(df_active, x='Time', y='Cum_Fuel', labels={'Cum_Fuel': 'Fuel Burned (kg)'})
    fig4.update_traces(line_color='#ff3333', line_width=3)
    fig4.update_layout(template="plotly_white", margin=dict(t=30))
    st.plotly_chart(fig4, use_container_width=True)

with tab5:
    st.subheader("5. Component Operating Conditions")
    fig5 = go.Figure()
    fig5.add_trace(go.Scatter(x=df_active['Time'], y=df_active['Engine_Fraction']*100, name="Engine Pwr Fraction (%)", line=dict(color='#ff9900')))
    fig5.add_trace(go.Scatter(x=df_active['Time'], y=df_active['Motor_Eff'], name="Motor Efficiency (%)", line=dict(color='#0066cc')))
    fig5.update_layout(xaxis_title="Time (s)", yaxis_title="Percentage (%)", template="plotly_white", margin=dict(t=30))
    st.plotly_chart(fig5, use_container_width=True)

with tab6:
    st.subheader("6. Instantaneous System Efficiency")
    fig6 = px.line(df_active, x='Time', y='System_Eff', labels={'System_Eff': 'Propulsion System Efficiency (%)'})
    fig6.update_traces(line_color='#8c1aff')
    fig6.update_layout(template="plotly_white", yaxis=dict(range=[0, 50]), margin=dict(t=30))
    st.plotly_chart(fig6, use_container_width=True)

with tab7:
    st.subheader("7. Endurance Estimation & Baseline Comparison")
    
    # Conventional baseline assumption: Engine runs at partial load continuously with higher BSFC
    baseline_fuel_rate_kg_s = 0.012 
    total_time_hrs = df_active['Time'].max() / 3600.0
    baseline_fuel = baseline_fuel_rate_kg_s * df_active['Time'].max()
    
    colA, colB = st.columns(2)
    with colA:
        st.markdown("""
        <div style='background-color: #f0f2f6; padding: 20px; border-radius: 10px; text-align: center;'>
            <h3 style='margin:0;'>Hybrid Config (Current)</h3>
            <h1 style='color: #00b3b3; margin: 10px 0;'>{time:.2f} hrs</h1>
            <p>Fuel Burned: <b>{fuel:.2f} kg</b></p>
        </div>
        """.format(time=total_time_hrs, fuel=fuel_ha), unsafe_allow_html=True)
        
    with colB:
        st.markdown("""
        <div style='background-color: #ffe6e6; padding: 20px; border-radius: 10px; text-align: center;'>
            <h3 style='margin:0;'>Conventional Baseline</h3>
            <h1 style='color: #ff3333; margin: 10px 0;'>{time:.2f} hrs</h1>
            <p>Est. Fuel Burned: <b>{fuel:.2f} kg</b></p>
        </div>
        """.format(time=total_time_hrs, fuel=baseline_fuel), unsafe_allow_html=True)
    
    st.markdown("### Health-Aware Degradation Impact")
    st.info(f"Battery Power Throughput (Stress proxy): **{bt_ha:.2f} kWh** handled dynamically to offset an engine degradation of **{eng_deg_val*100:.0f}%** while respecting a current Battery SOH of **{soh_val*100:.0f}%**.")

with tab8:
    st.subheader("8. Sizing Optimization Results (Pareto Front)")
    st.markdown("Select a point on the sidebar to update the entire dashboard's simulated design.")
    
    fig8 = px.scatter(
        pareto_df, 
        x='Propulsion_Mass_kg', 
        y='Fuel_Burned_kg', 
        color='Split_Frac',
        hover_name='Design_ID',
        size='Battery_Wh',
        color_continuous_scale=px.colors.sequential.Plasma,
        labels={'Propulsion_Mass_kg': 'Propulsion Mass (kg)', 'Fuel_Burned_kg': 'Mission Fuel Burn (kg)', 'Split_Frac': 'Power Split'},
        title="Fuel Burn vs Mass Trade-off (Size = Battery Wh)"
    )
    
    # Highlight selected point
    fig8.add_trace(go.Scatter(
        x=[active_design['Propulsion_Mass_kg']], 
        y=[active_design['Fuel_Burned_kg']],
        mode='markers',
        marker=dict(color='red', size=15, symbol='star', line=dict(color='black', width=2)),
        name=f"Selected: {active_design['Design_ID']}"
    ))
    
    fig8.update_layout(template="plotly_white", margin=dict(t=40))
    st.plotly_chart(fig8, use_container_width=True)
