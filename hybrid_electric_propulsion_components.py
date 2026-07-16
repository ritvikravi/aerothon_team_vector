import numpy as np
from scipy.interpolate import interp1d

def get_isa_density_ratio(altitude_m: float) -> float:
    """
    Computes the International Standard Atmosphere (ISA) density ratio for a given altitude.
    Simplified standard atmosphere model valid up to the lower stratosphere (~20km).
    """
    altitude_m = max(0.0, altitude_m)
    
    # Constants
    T_0 = 288.15        # Sea level standard temperature [K]
    p_0 = 101325.0      # Sea level standard pressure [Pa]
    R_spec = 287.05     # Specific gas constant for dry air [J/(kg*K)]
    g_0 = 9.80665       # Gravity [m/s^2]
    rho_0 = 1.225       # Sea level standard density [kg/m^3]
    
    if altitude_m <= 11000.0:
        # Troposphere
        lapse_rate = -0.0065
        T = T_0 + lapse_rate * altitude_m
        p = p_0 * (T / T_0) ** (-g_0 / (lapse_rate * R_spec))
    else:
        # Tropopause and lower Stratosphere
        T_11k = 216.65
        p_11k = p_0 * (T_11k / T_0) ** 5.25588
        T = T_11k
        p = p_11k * np.exp(-g_0 * (altitude_m - 11000.0) / (R_spec * T))
        
    rho = p / (R_spec * T)
    return rho / rho_0

class TurboshaftEngine:
    """
    Simplified model of a UAV turboshaft engine for preliminary sizing.
    Uses generic literature-derived curves for altitude lapse and part-load efficiency.
    """
    
    def __init__(self, rated_power_kW: float, rated_SFC: float):
        """
        :param rated_power_kW: Maximum sea-level static power in kW.
        :param rated_SFC: Specific Fuel Consumption at rated power in kg/kWh.
        """
        self.rated_power_kW = rated_power_kW
        self.rated_SFC = rated_SFC
        
        # ---------------------------------------------------------------------
        # Literature Note: 
        # The following curve reflects the standard finding that gas turbine 
        # part-load BSFC is significantly worse than rated-power BSFC. 
        # For detailed design, this should be replaced with a real 
        # datasheet-derived curve from a specific engine (e.g., PBS TP-R90).
        # ---------------------------------------------------------------------
        power_fractions = np.array([0.2, 0.4, 0.6, 0.8, 1.0])
        bsfc_multipliers = np.array([1.45, 1.20, 1.08, 1.02, 1.00])
        
        # We allow extrapolation for transient overloading or very low idle
        self._bsfc_curve = interp1d(
            power_fractions, bsfc_multipliers, 
            kind='linear', fill_value="extrapolate"
        )

    def power_available(self, altitude_m: float, mach: float = 0.0) -> float:
        """
        Calculates maximum available power at a given altitude.
        
        Literature Note:
        Uses the standard simplified turboshaft altitude lapse approximation:
        P_avail = P_rated * (sigma ^ 0.7) where sigma is the ISA density ratio.
        Mach/ram recovery effects are neglected in this simple zero-order model.
        """
        density_ratio = get_isa_density_ratio(altitude_m)
        lapse_factor = density_ratio ** 0.7
        return self.rated_power_kW * lapse_factor

    def bsfc(self, power_fraction: float) -> float:
        """
        Returns the specific fuel consumption (kg/kWh) at a given power fraction.
        """
        # Constrain extreme values to prevent unphysical negative/zero extrapolation
        pf = max(0.05, min(power_fraction, 1.2)) 
        multiplier = float(self._bsfc_curve(pf))
        return self.rated_SFC * multiplier

    def fuel_flow_kg_s(self, power_kW: float, altitude_m: float, mach: float = 0.0) -> float:
        """
        Calculates instantaneous fuel flow in kg/s for a required power at altitude.
        """
        p_max = self.power_available(altitude_m, mach)
        
        if power_kW <= 0:
            return 0.0
            
        power_fraction = power_kW / p_max
        if power_fraction > 1.0:
            # We assume the engine might allow minor transient over-torque, 
            # but logically it is exceeding standard max continuous power.
            pass 
            
        current_bsfc = self.bsfc(power_fraction)
        
        # Fuel flow [kg/h] = power [kW] * BSFC [kg/kWh]
        # Fuel flow [kg/s] = (kg/h) / 3600
        return (power_kW * current_bsfc) / 3600.0


class BatteryPack:
    """
    Equivalent Circuit Model (ECM) of a Battery Pack.
    Includes voltage sag due to internal resistance and simplified SOC tracking.
    """
    def __init__(self, capacity_Wh: float, energy_density_Wh_per_kg: float = 265.0, 
                 internal_resistance_ohm: float = 0.05, nominal_voltage: float = 400.0):
        self.capacity_Wh = capacity_Wh
        self.energy_density = energy_density_Wh_per_kg
        self.R = internal_resistance_ohm
        self.V_nom = nominal_voltage
        self.soc = 1.0  # State of Charge (0.0 to 1.0)

    def terminal_voltage(self, current_A: float) -> float:
        """
        Calculates the terminal voltage under load using a basic OCV - I*R model.
        Assumes Open Circuit Voltage (OCV) is roughly nominal for simplicity.
        """
        return max(0.0, self.V_nom - (current_A * self.R))

    def usable_energy(self, discharge_rate_C: float) -> float:
        """
        Derates nominal capacity for high discharge rates due to voltage sag.
        """
        # Determine the steady-state current for this C-rate
        current_A = discharge_rate_C * (self.capacity_Wh / self.V_nom)
        
        # Calculate terminal voltage under this load
        v_term = self.terminal_voltage(current_A)
        
        # Energy derating approximated by the ratio of operating voltage to nominal voltage
        derating_factor = v_term / self.V_nom
        
        return self.capacity_Wh * derating_factor

    def update_soc(self, power_kW: float, dt_s: float):
        """
        Updates the State of Charge (SOC) based on power drawn over a time step.
        (Positive power means discharge, negative means charge).
        """
        energy_kWh = power_kW * (dt_s / 3600.0)
        capacity_kWh = self.capacity_Wh / 1000.0
        
        self.soc -= (energy_kWh / capacity_kWh)
        self.soc = max(0.0, min(self.soc, 1.0)) # Bind between 0 and 100%

    def mass_kg(self) -> float:
        """
        Returns total pack mass based on capacity and pack-level energy density.
        """
        return self.capacity_Wh / self.energy_density


class ElectricMotor:
    """
    Simple Electric Motor model with quadratic part-load efficiency derating.
    """
    def __init__(self, rated_power_kW: float, peak_efficiency: float = 0.93):
        self.rated_power_kW = rated_power_kW
        self.peak_eff = peak_efficiency
        
    def efficiency(self, power_fraction: float) -> float:
        """
        Returns motor efficiency. 
        Assumes peak efficiency occurs near a power fraction of 0.7, 
        with a quadratic derating at very low and very high power settings.
        """
        pf = max(0.01, min(power_fraction, 1.2))
        peak_fraction = 0.7
        
        # Quadratic derating: eff = peak_eff - k * (delta_fraction)^2
        # Constant k is tuned so efficiency drops ~7-8% at 10% load.
        k_derating = 0.2 
        
        eff = self.peak_eff - k_derating * (pf - peak_fraction)**2
        return float(max(0.1, eff))


if __name__ == "__main__":
    # Instantiate realistic components
    turboshaft = TurboshaftEngine(rated_power_kW=60.0, rated_SFC=0.35)
    battery = BatteryPack(capacity_Wh=15000.0, internal_resistance_ohm=0.08, nominal_voltage=400.0)
    motors = [ElectricMotor(rated_power_kW=15.0) for _ in range(4)]
    
    print("-" * 50)
    print("HYBRID-ELECTRIC COMPONENT SANITY CHECK")
    print("-" * 50)
    
    # 1. Turboshaft Engine altitude lapse and BSFC check
    print("\n[ Turboshaft Engine: 60 kW, 0.35 kg/kWh rated SFC ]")
    p_sl = turboshaft.power_available(altitude_m=0)
    p_10k = turboshaft.power_available(altitude_m=10000)
    print(f"Max Power (Sea Level): {p_sl:.2f} kW")
    print(f"Max Power (10 km alt): {p_10k:.2f} kW")
    
    print("BSFC mapping:")
    for pct in [20, 60, 100]:
        pf = pct / 100.0
        val_bsfc = turboshaft.bsfc(pf)
        print(f"  - @ {pct:3d}% power: {val_bsfc:.3f} kg/kWh")
        
    # 2. Battery pack derating check
    print(f"\n[ Battery Pack: 15 kWh, {battery.mass_kg():.1f} kg, 400 V nominal ]")
    e_1c = battery.usable_energy(discharge_rate_C=1.0)
    e_3c = battery.usable_energy(discharge_rate_C=3.0)
    print(f"Usable Energy @ 1C: {e_1c/1000:.2f} kWh")
    print(f"Usable Energy @ 3C: {e_3c/1000:.2f} kWh")
    
    # 3. Electric motor check
    print("\n[ Electric Motors: 4x 15 kW (60kW total) ]")
    for pct in [10, 70, 100]:
        pf = pct / 100.0
        eff = motors[0].efficiency(pf)
        print(f"Motor Eff @ {pct:3d}% power: {eff*100:.1f} %")
    
    print("-" * 50)
