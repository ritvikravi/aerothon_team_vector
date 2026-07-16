function [endurance_s, g] = evaluateMission(designStruct, archFcn)
%EVALUATEMISSION Rigorous physics-based aerodynamic and component sizing model.

% 1. FIXED AIRCRAFT PARAMETERS (From your table)
MTOW_kg = 1000;
payload_kg = 200;
structure_kg = 350; 
wingArea_m2 = 12.0; 
AR = 10; 
e0 = 0.8;
Cd0 = 0.025;
eta_prop = 0.85; % Propeller efficiency
socReserve = 0.20;

% 2. COMPONENT MASS SCALING (Vigorous Math)
% Specific powers: Engine ~ 2.5 kW/kg, Motor ~ 3.5 kW/kg, Battery ~ 250 Wh/kg
massEngine_kg  = designStruct.engineSize_kW / 2.5;
massMotors_kg  = (designStruct.engineSize_kW * 0.8) / 3.5; % Sized to match 80% engine power
massBattery_kg = (designStruct.batteryCap_kWh * 1000) / 250;

% Calculate available weight for fuel
emptyMass_kg = structure_kg + massEngine_kg + massMotors_kg + massBattery_kg;
fuelCapacity_kg = MTOW_kg - emptyMass_kg - payload_kg;

% Constraint 1: Aircraft empty weight exceeds MTOW!
g1_MTOW = -fuelCapacity_kg; 

% 3. AERODYNAMIC ENVIRONMENT SETUP
rho0 = 1.225; 
K = 1 / (pi * e0 * AR); % Induced drag factor
batteryCapEnergy_J = designStruct.batteryCap_kWh * 3.6e6;
maxEnginePower_W = designStruct.engineSize_kW * 1000;

% Phase profiles: [Altitude(m), Velocity(m/s), Duration(s)]
% Note: Cruise duration is set to 1 sec here; we calculate true endurance later.
phases = {'takeoff', 'climb', 'cruise', 'loiter', 'descent'};
alt_m  = [0, 1500, 3000, 3000, 1500];
vel_mps = [25, 30, 69.4, 40, 30]; % 69.4 m/s is ~250 km/h
dur_s  = [60, 300, 1, 900, 300]; 

fuelUsed_kg = 0;
batteryEnergy_J = batteryCapEnergy_J;
worstShortfall_W = 0;

missionState = struct('altitude_m', 0, 'speed_mps', 0, 'powerRequired_W', 0, 'batterySoC', 1.0, 'timeElapsed_s', 0);

% 4. MISSION SIMULATION
fuelBurnRate_cruise_kgps = 0; % Track this to calculate endurance later

for i = 1:5
    % Aero math: Density at altitude
    rho = rho0 * (1 - 2.25577e-5 * alt_m(i))^4.2561;
    
    % Aero math: Lift and Drag
    W_N = MTOW_kg * 9.81; % Assuming constant weight for power sizing to be conservative
    CL = (2 * W_N) / (rho * vel_mps(i)^2 * wingArea_m2);
    CD = Cd0 + K * CL^2;
    
    % Power required at propeller
    P_req_W = (0.5 * rho * vel_mps(i)^3 * wingArea_m2 * CD) / eta_prop;
    
    % Update State
    missionState.altitude_m = alt_m(i);
    missionState.speed_mps = vel_mps(i);
    missionState.powerRequired_W = P_req_W;
    missionState.batterySoC = max(batteryEnergy_J, 0) / batteryCapEnergy_J;
    
    % Architecture routing
    pShare = archFcn(designStruct, phases{i}, missionState);
    pShare = min(max(pShare,0),1); 
    
    electricPower_W = pShare * P_req_W;
    thermalPower_W  = (1 - pShare) * P_req_W;
    
    if thermalPower_W > maxEnginePower_W
        worstShortfall_W = max(worstShortfall_W, thermalPower_W - maxEnginePower_W);
        thermalPower_W = maxEnginePower_W;
    end
    
    % Engine SFC Math (Throttle dependent)
    throttle = max(thermalPower_W / maxEnginePower_W, 0.05); 
    % Vigorous SFC curve: High consumption at low throttle
    SFC_kg_per_Ws = 8e-8 * (0.8 + 0.15/throttle + 0.05*throttle); 
    
    if strcmp(phases{i}, 'cruise')
        fuelBurnRate_cruise_kgps = thermalPower_W * SFC_kg_per_Ws;
        electricBurnRate_cruise_W = electricPower_W;
    else
        % Deduct energy for fixed-duration phases
        batteryEnergy_J = batteryEnergy_J - (electricPower_W * dur_s(i));
        fuelUsed_kg = fuelUsed_kg + (thermalPower_W * SFC_kg_per_Ws * dur_s(i));
    end
end

% 5. CALCULATE CRUISE ENDURANCE
fuelAvailableForCruise = max(fuelCapacity_kg - fuelUsed_kg, 0);
batteryAvailableForCruise_J = max(batteryEnergy_J - (socReserve * batteryCapEnergy_J), 0);

% How long can we fly based on fuel?
if fuelBurnRate_cruise_kgps > 0
    endurance_fuel_s = fuelAvailableForCruise / fuelBurnRate_cruise_kgps;
else
    endurance_fuel_s = inf;
end

% How long can we fly based on battery?
if electricBurnRate_cruise_W > 0
    endurance_batt_s = batteryAvailableForCruise_J / electricBurnRate_cruise_W;
else
    endurance_batt_s = inf;
end

% Total cruise time is limited by whichever runs out first
cruiseEndurance_s = min(endurance_fuel_s, endurance_batt_s);
if isinf(cruiseEndurance_s), cruiseEndurance_s = 0; end

% 6. CONSTRAINTS & OUTPUT
g2_SoC = 0; % Handled by limiting endurance
g3_Power = worstShortfall_W; 
g4_Fuel = fuelUsed_kg - fuelCapacity_kg; % Must have enough fuel for takeoff/climb/loiter

g = [g1_MTOW; g2_SoC; g3_Power; g4_Fuel];

% Total endurance = fixed phases + calculated cruise
totalEndurance_s = sum(dur_s) - 1 + cruiseEndurance_s; 
endurance_s = totalEndurance_s;

end