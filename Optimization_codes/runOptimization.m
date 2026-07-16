%% runOptimization.m
% Entry point: wires together design variables, power-sharing architecture,
% physics-based mission evaluator, and the mixed-variable PSO solver.
clear; clc; close all;

% 1) Initialize Specifications & Handles
varSpec = designVectorSpec();
archFcn = @exampleArchitecture;
missionFcn = @evaluateMission; 

% 2) Objective Definition with Quadratic Penalty
penaltyWeight = 100;
objFcn = @(designStruct) objectiveWrapper(designStruct, missionFcn, archFcn, penaltyWeight);

% 3) Configured Particle Swarm Settings
opts = struct('swarmSize', 50, 'maxIter', 150, 'w0', 0.9, 'wMin', 0.4, ...
              'c1', 1.5, 'c2', 1.5, 'vMaxFrac', 0.2, 'tolFun', 1e-4, ...
              'stallIterMax', 30, 'seed', 42, 'verbose', true, 'useParallel', false);

% 4) Execute Solver Execution Pipeline
fprintf('=============================================================\n');
fprintf('     LAUNCHING HYBRID PROPULSION PSO ADVANCED SOLVER        \n');
fprintf('=============================================================\n');
tStart = tic;
[bestDesign, bestFval, history] = pso(objFcn, varSpec, opts);
elapsed_s = toc(tStart);

% 5) Display Key Optimization Insights
fprintf('\n=============================================================\n');
fprintf('                OPTIMIZATION COMPLETE RESULTS                \n');
fprintf('=============================================================\n');
disp(bestDesign);
fprintf('Maximized Flight Endurance: %.2f Hours\n', -bestFval / 3600);
fprintf('Total Algorithm Execution Time: %.2f Seconds\n', elapsed_s);

%% =========================================================================
%                  SCIENTIFIC VISUAL ANALYTICS SUITE
%  =========================================================================
fprintf('\nGenerating Scientific Analytics Figures Suite... \n');

% Figure 1: Core Performance Dashboard (Convergence, Weights, Power Profile)
plotCoreDashboard(bestDesign, bestFval, history, archFcn);

% Figure 2: The Sizing Topology Landscape & Swarm Convergence Mapping
plotDesignSpaceTopology(varSpec, bestDesign, bestFval, missionFcn, archFcn);

% Figure 3: Aerodynamic Polar & Lift-to-Drag Efficiency Maps
plotAerodynamicPolarMap();

% Figure 4: Continuous Non-Linear Turboshaft Engine Operating SFC Map
plotEngineOperatingMap(bestDesign, archFcn);

% Figure 5: Multi-Phase Thermodynamic Energy Waterfall/Cascade
plotEnergyCascade(bestDesign, archFcn);

% Figure 6: Dynamic Blueprint Architecture Layout & Command Table
plotOptimizedArchitecture(bestDesign, bestFval);

fprintf('All visualization figures and tables successfully rendered.\n');


%% =========================================================================
%                  LOCAL VISUALIZATION HELPER FUNCTIONS
%  =========================================================================

function plotCoreDashboard(designStruct, bestFval, history, archFcn)
    % PLOTCOREDASHBOARD Renders convergence, mass distribution, and system power splits.
    phases = {'takeoff', 'climb', 'cruise', 'loiter', 'descent'};
    alt_m  = [0, 1500, 3000, 3000, 1500];
    vel_mps = [25, 30, 69.4, 40, 30]; 
    
    % Re-calculate subsystem weights using engineering equations
    mEng = designStruct.engineSize_kW / 2.5;
    mMot = (designStruct.engineSize_kW * 0.8) / 3.5;
    mBat = (designStruct.batteryCap_kWh * 1000) / 250;
    mEmpty = 350 + mEng + mMot + mBat;
    mFuel = max(1000 - mEmpty - 200, 0);
    
    pReq = zeros(1,5); pElec = zeros(1,5); pEng = zeros(1,5);
    missionState = struct('altitude_m', 0, 'speed_mps', 0, 'powerRequired_W', 0, 'batterySoC', 1.0, 'timeElapsed_s', 0);
    
    for i = 1:5
        rho = 1.225 * (1 - 2.25577e-5 * alt_m(i))^4.2561;
        CL = (2 * 1000 * 9.81) / (rho * vel_mps(i)^2 * 12.0);
        CD = 0.025 + (1 / (pi * 0.8 * 10)) * CL^2;
        pReq(i) = ((0.5 * rho * vel_mps(i)^3 * 12.0 * CD) / 0.85) / 1000; 
        
        pShare = archFcn(designStruct, phases{i}, missionState);
        pElec(i) = pReq(i) * pShare;
        pEng(i) = pReq(i) * (1 - pShare);
    end
    
    figure('Name', 'System Performance Diagnostics', 'Position', [50, 50, 1300, 850], 'Color', 'w');
    
    % Subplot A: Optimization Trajectory
    subplot(2,2,1);
    plot(history.bestFval / -3600, 'LineWidth', 2.5, 'Color', '#0072BD');
    grid on; xlabel('Iteration Index', 'FontWeight', 'bold'); ylabel('Endurance Output (Hours)', 'FontWeight', 'bold');
    title('Particle Swarm Objective Convergence History', 'FontSize', 11, 'FontWeight', 'bold');
    
    % Subplot B: MTOW Weight Breakdown
    subplot(2,2,2);
    pieData = [mEng, mMot, mBat, mFuel, 350, 200];
    pieLabels = {'Engine', 'Motors', 'Battery', 'Fuel Load', 'Airframe Structure', 'Payload'};
    pie(pieData); title(sprintf('1000 kg Maximum Takeoff Weight Partition\nAvailable Fuel: %.1f kg', mFuel), 'FontSize', 11, 'FontWeight', 'bold');
    legend(pieLabels, 'Location', 'eastoutside');
    
    % Subplot C: Power Allocation Stacked Bars
    subplot(2,2,3);
    barChart = bar([pEng; pElec]', 'stacked', 'EdgeColor', 'k');
    barChart(1).FaceColor = '#D95319'; barChart(2).FaceColor = '#4DBEEE';
    set(gca, 'XTickLabel', phases); grid on;
    ylabel('Power Profile Demand (kW)', 'FontWeight', 'bold');
    title('Optimized Operational Power Distribution Across Flight Profile', 'FontSize', 11, 'FontWeight', 'bold');
    legend('Thermal Engine Output', 'Electric Motor Output', 'Location', 'northeast');
    
    % Subplot D: Architecture Variable Breakdown
    subplot(2,2,4);
    splits = [designStruct.split_takeoff, designStruct.split_climb, designStruct.split_cruise, designStruct.split_loiter, designStruct.split_descent] * 100;
    bar(splits, 0.5, 'FaceColor', '#7E2F8E', 'EdgeColor', 'k');
    set(gca, 'XTickLabel', phases); ylim([0 105]); grid on;
    ylabel('Electric Assistance Fraction (%)', 'FontWeight', 'bold');
    title('Optimizer Calculated Multi-Phase Power Split Matrix', 'FontSize', 11, 'FontWeight', 'bold');
end

function plotDesignSpaceTopology(varSpec, bestDesign, bestFval, missionFcn, archFcn)
    % PLOTDESIGNSPACETOPOLOGY Generates a scientific 3D landscape layout.
    engLimits = linspace(varSpec(1).lb, varSpec(1).ub, 25);
    batLimits = linspace(varSpec(2).lb, varSpec(2).ub, 25);
    [EngGrid, BatGrid] = meshgrid(engLimits, batLimits);
    EnduranceZ = zeros(size(EngGrid));
    IsFeasible = true(size(EngGrid));
    
    tempSpec = bestDesign;
    penaltyWeight = 100;
    
    for r = 1:size(EngGrid, 1)
        for c = 1:size(EngGrid, 2)
            tempSpec.engineSize_kW = EngGrid(r,c);
            tempSpec.batteryCap_kWh = BatGrid(r,c);
            [endurance_s, g] = missionFcn(tempSpec, archFcn);
            violation = sum(max(0, g).^2);
            EnduranceZ(r,c) = (-endurance_s + penaltyWeight * violation) / -3600;
            if any(g > 0), IsFeasible(r,c) = false; end
        end
    end
    
    EnduranceZ(EnduranceZ < -0.5) = -0.5; 
    
    figure('Name', 'System Sizing Topology Landscape', 'Position', [150, 100, 950, 700], 'Color', 'w');
    meshSurf = surf(EngGrid, BatGrid, EnduranceZ, 'EdgeColor', 'none', 'FaceAlpha', 0.85);
    colormap(gca, jet(256)); colorbar; hold on;
    shading interp; camlight; lighting phong;
    
    contour3(EngGrid, BatGrid, double(IsFeasible)*2, 1, 'r-', 'LineWidth', 2.5);
    
    plot3(bestDesign.engineSize_kW, bestDesign.batteryCap_kWh, -bestFval/3600 + 0.1, ...
          'm*', 'MarkerSize', 16, 'LineWidth', 3);
      
    xlabel('Engine Continuous Sizing (kW)', 'FontWeight', 'bold');
    ylabel('Battery Capacity Sizing (kWh)', 'FontWeight', 'bold');
    zlabel('System Performance Metric (Endurance, Hours)', 'FontWeight', 'bold');
    title('3D Multi-Variable Sizing Domain & Structural Constraint Boundaries', 'FontSize', 12, 'FontWeight', 'bold');
    legend('Performance Boundary Domain', 'Constraint Limits Boundaries (g_i = 0)', 'Global Optimized Solution (PSO)', ...
           'Location', 'northeast');
    view(-55, 35); grid on;
end

function plotAerodynamicPolarMap()
    % PLOTAERODYNAMICPOLARMAP Draws the aerodynamic efficiency mapping.
    vel_range = linspace(15, 90, 150); 
    rho = 1.225; S = 12.0; mass = 1000; g = 9.81;
    Cd0 = 0.025; K = 1 / (pi * 0.8 * 10);
    
    W = mass * g;
    CL_vec = (2 * W) ./ (rho .* vel_range.^2 .* S);
    CD_vec = Cd0 + K .* CL_vec.^2;
    L_over_D = CL_vec ./ CD_vec;
    
    figure('Name', 'Aerodynamic Performance Polar Map', 'Position', [250, 150, 1100, 500], 'Color', 'w');
    
    subplot(1,2,1);
    plot(CD_vec, CL_vec, 'LineWidth', 2.5, 'Color', '#A2142F'); grid on;
    xlabel('Total Drag Coefficient (C_D)', 'FontWeight', 'bold');
    ylabel('Total Lift Coefficient (C_L)', 'FontWeight', 'bold');
    title('System Aerodynamic Polar Chart Profile (C_L vs C_D)', 'FontSize', 11, 'FontWeight', 'bold');
    
    subplot(1,2,2);
    plot(vel_range * 3.6, L_over_D, 'LineWidth', 2.5, 'Color', '#77AC30'); grid on;
    hold on;
    
    [maxLD, idxMax] = max(L_over_D);
    plot(vel_range(idxMax)*3.6, maxLD, 'kx', 'MarkerSize', 12, 'LineWidth', 2);
    text(vel_range(idxMax)*3.6 + 2, maxLD - 0.5, sprintf('(L/D)_{max} = %.1f', maxLD), 'FontWeight', 'bold');
    
    phases = {'Takeoff', 'Climb', 'Cruise', 'Loiter', 'Descent'};
    vOps = [25, 30, 69.4, 40, 30] * 3.6;
    for p = 1:5
        cLOp = (2 * W) / (rho * (vOps(p)/3.6)^2 * S);
        cDOp = Cd0 + K * cLOp^2;
        ldOp = cLOp / cDOp;
        plot(vOps(p), ldOp, 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 6);
        text(vOps(p) + 1.5, ldOp, phases{p}, 'FontSize', 9);
    end
    
    xlabel('Airspeed (km/h)', 'FontWeight', 'bold');
    ylabel('Aerodynamic Efficiency Ratio (L/D)', 'FontWeight', 'bold');
    title('Operational Airspeed vs Lift-to-Drag Operational Vectors', 'FontSize', 11, 'FontWeight', 'bold');
end

function plotEngineOperatingMap(bestDesign, archFcn)
    % PLOTENGINEOPERATINGMAP Tracks fuel burn rate behavior under partial throttle conditions.
    tRange = linspace(0.05, 1.0, 100);
    sfcNominal = 0.32;
    sfcModel = sfcNominal * (0.7 + 0.25./tRange + 0.05*tRange.^2);
    
    phases = {'takeoff', 'climb', 'cruise', 'loiter', 'descent'};
    pReq = [55, 45, 20, 15, 5]; 
    tPoints = zeros(1, 5); sfcPoints = zeros(1, 5);
    mState = struct('altitude_m', 0, 'speed_mps', 0, 'powerRequired_W', 0, 'batterySoC', 1.0);
    
    for i = 1:5
        pShare = archFcn(bestDesign, phases{i}, mState);
        pEng = pReq(i) * (1 - pShare);
        tau = min(max(pEng / bestDesign.engineSize_kW, 0.05), 1.0);
        tPoints(i) = tau;
        sfcPoints(i) = sfcNominal * (0.7 + 0.25/tau + 0.05*tau^2);
    end
    
    figure('Name', 'Turboshaft Fuel Efficiency Mapping', 'Position', [300, 200, 900, 520], 'Color', 'w');
    plot(tRange * 100, sfcModel, 'LineWidth', 2.5, 'Color', '#0072BD'); hold on; grid on;
    
    ptColors = {'#D95319', '#EDB120', '#7E2F8E', '#77AC30', '#4DBEEE'};
    for i = 1:5
        plot(tPoints(i)*100, sfcPoints(i), 's', 'MarkerSize', 11, ...
             'MarkerFaceColor', ptColors{i}, 'MarkerEdgeColor', 'k');
        text(tPoints(i)*100 + 2, sfcPoints(i) + 0.01, phases{i}, 'FontWeight', 'bold', 'FontSize', 9);
    end
    
    xlabel('Engine Operational Power Throttle (%)', 'FontWeight', 'bold');
    ylabel('Instant Specific Fuel Consumption (kg/kWh)', 'FontWeight', 'bold');
    title('Non-Linear Performance Brake Specific Fuel Consumption (BSFC) Map', 'FontSize', 12, 'FontWeight', 'bold');
    xlim([0, 110]);
end

function plotEnergyCascade(bestDesign, archFcn)
    % PLOTENERGYCASCADE Displays loss mechanics through the transmission steps.
    pReqBase = [55, 45, 20, 15, 5];
    mState = struct('altitude_m', 0, 'speed_mps', 0, 'powerRequired_W', 0, 'batterySoC', 1.0);
    
    pShare = archFcn(bestDesign, 'takeoff', mState);
    reqW = pReqBase(1);
    
    pElecMech = reqW * pShare;
    pThermalMech = reqW * (1 - pShare);
    
    pFuelInput = pThermalMech / 0.35; 
    pBatteryInput = pElecMech / 0.90; 
    
    lossThermal = pFuelInput - pThermalMech;
    lossElec = pBatteryInput - pElecMech;
    lossProp = reqW * (1 - 0.85);
    pNetAero = reqW - lossProp;
    
    cascadeVals = [pFuelInput + pBatteryInput, -lossThermal, -lossElec, -lossProp, -pNetAero * 0.45, -pNetAero * 0.55];
    cascadeLabels = {'Gross System Input', 'Thermal Core Losses', 'Electrical/ESC Losses', ...
                     'Propeller Mechanical Slips', 'Aerodynamic Induced Drag', 'Parasitic Skin Friction'};
                 
    cumulVector = cumsum([0, cascadeVals(1:end-1)]);
    
    figure('Name', 'System Power Degradation Chain', 'Position', [350, 250, 950, 520], 'Color', 'w');
    
    for k = 1:numel(cascadeVals)
        cColor = '#77AC30'; if cascadeVals(k) < 0, cColor = '#D95319'; end
        rectangle('Position', [k-0.35, cumulVector(k) + min(cascadeVals(k),0), 0.7, abs(cascadeVals(k))], ...
                  'FaceColor', cColor, 'EdgeColor', 'k', 'LineWidth', 1.1);
        hold on;
        text(k, cumulVector(k) + cascadeVals(k)/2, sprintf('%.1f kW', abs(cascadeVals(k))), ...
             'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold', 'FontSize', 9);
    end
    
    set(gca, 'XTick', 1:numel(cascadeLabels), 'XTickLabel', cascadeLabels, 'XTickLabelRotation', 15);
    ylabel('Power Scale Amplitude (kW)', 'FontWeight', 'bold');
    title('Thermodynamic & Aerodynamic Energy Degradation Cascade (Takeoff Phase)', 'FontSize', 12, 'FontWeight', 'bold');
    grid on; ylim([0, max(cumulVector)*1.1]);
end

function plotOptimizedArchitecture(designStruct, bestFval)
    % PLOTOPTIMIZEDARCHITECTURE Generates a formatted command window table
    % and renders a custom 2D schematic blueprint of the parallel hybrid powertrain.
    
    %% 1. COMMAND WINDOW SUMMARY TABLE
    fprintf('\n=============================================================\n');
    fprintf('           OPTIMIZED PROPULSION SYSTEM ARCHITECTURE          \n');
    fprintf('=============================================================\n');
    
    % Renamed to avoid reserved dimension collisions with MATLAB 'table' keyword
    Component_Parameter = {
        'Turboshaft Engine Capacity';
        'Battery Storage Capacity';
        'Configured Propulsion Motors';
        'Takeoff Electric Share (u_e)';
        'Climb Electric Share (u_e)';
        'Cruise Electric Share (u_e)';
        'Loiter Electric Share (u_e)';
        'Descent Electric Share (u_e)'
    };
    
    Optimized_Value = [
        designStruct.engineSize_kW;
        designStruct.batteryCap_kWh;
        designStruct.numMotors;
        designStruct.split_takeoff;
        designStruct.split_climb;
        designStruct.split_cruise;
        designStruct.split_loiter;
        designStruct.split_descent
    ];
    
    Physical_Units = {'kW'; 'kWh'; 'units'; 'fraction'; 'fraction'; 'fraction'; 'fraction'; 'fraction'};
    
    % Generate clean layout table tracking custom arrays
    SummaryTable = table(Component_Parameter, Optimized_Value, Physical_Units);
    disp(SummaryTable);
    
    %% 2. DYNAMIC SCHEMATIC BLUEPRINT GENERATION
    fig = figure('Name', 'Optimized Powertrain Architecture Blueprint', ...
                 'Position', [400, 200, 1000, 600], 'Color', 'w');
    ax = axes('Parent', fig);
    hold(ax, 'on');
    grid(ax, 'off');
    box(ax, 'on');
    set(ax, 'XTick', [], 'YTick', [], 'XColor', 'none', 'YColor', 'none');
    xlim(ax, [0, 12]); ylim(ax, [0, 8]);
    title(ax, sprintf('Optimized Parallel-Hybrid Powertrain Schematic Topology\nMaximized Flight Endurance: %.2f Hours', -bestFval/3600), ...
          'FontSize', 13, 'FontWeight', 'bold');

    engkW = designStruct.engineSize_kW;
    batkWh = designStruct.batteryCap_kWh;
    nMots = designStruct.numMotors;
    
    engHeight = 1.0 + (engkW / 150) * 1.2; 
    batHeight = 1.0 + (batkWh / 60) * 1.2;  
    
    % Fuel Tank Block
    rectangle('Position', [1, 5.5, 1.8, 1.2], 'Curvature', 0.2, 'FaceColor', '#F5F5F5', 'EdgeColor', 'k', 'LineWidth', 1.5);
    text(1.9, 6.1, 'Fuel Storage\nTank', 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'FontSize', 9);
    
    % Turboshaft Engine Block (Scales visually with capacity sizing)
    rectangle('Position', [3.8, 6.1 - engHeight/2, 2.2, engHeight], 'Curvature', 0.1, ...
              'FaceColor', '#D95319', 'EdgeColor', 'k', 'LineWidth', 2);
    text(4.9, 6.1, sprintf('Turboshaft Engine\n%.1f kW', engkW), ...
         'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold', 'FontSize', 10);
     
    % Battery Storage Block (Scales visually with capacity sizing)
    rectangle('Position', [1, 1.5 - batHeight/2, 1.8, batHeight], 'Curvature', 0.05, ...
              'FaceColor', '#4DBEEE', 'EdgeColor', 'k', 'LineWidth', 2);
    text(1.9, 1.5, sprintf('Lithium Battery\nPack\n%.1f kWh', batkWh), ...
         'HorizontalAlignment', 'center', 'Color', 'k', 'FontWeight', 'bold', 'FontSize', 10);
     
    % Electric Motors Block Array
    rectangle('Position', [3.8, 0.7, 2.2, 1.6], 'Curvature', 0.1, ...
              'FaceColor', '#77AC30', 'EdgeColor', 'k', 'LineWidth', 2);
    text(4.9, 1.5, sprintf('Electric Motors\n(%d x Coaxial Units)', nMots), ...
         'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold', 'FontSize', 10);
     
    % Mechanical Summing Gearbox Block (Central Parallel Node)
    rectangle('Position', [7.5, 2.5, 1.4, 3.2], 'Curvature', 0.1, 'FaceColor', '#7E2F8E', 'EdgeColor', 'k', 'LineWidth', 2);
    text(8.2, 4.1, 'Mechanical\nSumming\nGearbox\n(Parallel)', ...
         'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold', 'FontSize', 9);
     
    % Aero Propeller Hub Array
    rectangle('Position', [10.2, 3.6, 0.4, 1.0], 'Curvature', 0.5, 'FaceColor', [0.2 0.2 0.2], 'EdgeColor', 'k');
    plot([10.4, 10.4], [1.5, 6.7], 'k-', 'LineWidth', 3); 
    text(10.9, 4.1, 'Propeller\nAssembly\n(\eta_p = 0.85)', 'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'FontSize', 9);

    % Transmission Line Traces
    annotation('arrow', [0.26, 0.33], [0.77, 0.77], 'LineWidth', 1.5, 'Color', 'k');
    plot([2.8, 3.8], [6.1, 6.1], 'k--', 'LineWidth', 1.5);
    
    plot([6.0, 7.5], [6.1, 5.0], 'Color', '#D95319', 'LineWidth', 3);
    text(6.75, 5.8, 'Engine Clutch', 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    plot([2.8, 3.8], [1.5, 1.5], 'Color', '#4DBEEE', 'LineWidth', 2.5);
    
    plot([6.0, 7.5], [1.5, 3.2], 'Color', '#77AC30', 'LineWidth', 3);
    text(6.75, 2.1, 'Motor Clutch', 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    
    plot([8.9, 10.2], [4.1, 4.1], 'k-', 'LineWidth', 4);
    text(9.5, 4.4, 'Thrust Shaft', 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    % Phase Split Text Box Panel Overlay
    rectangle('Position', [7.8, 6.2, 3.8, 1.5], 'Curvature', 0.05, 'FaceColor', '#FFFFE0', 'EdgeColor', '#EDB120', 'LineWidth', 1.2);
    text(7.9, 7.4, 'Optimized Operational Split (\nu_e):', 'FontWeight', 'bold', 'FontSize', 8.5);
    text(7.9, 7.05, sprintf('Takeoff: %.1f%% | Climb: %.1f%%', designStruct.split_takeoff*100, designStruct.split_climb*100), 'FontSize', 8);
    text(7.9, 6.75, sprintf('Cruise: %.1f%%  | Loiter: %.1f%%', designStruct.split_cruise*100, designStruct.split_loiter*100), 'FontSize', 8);
    text(7.9, 6.45, sprintf('Descent: %.2f%%', designStruct.split_descent*100), 'FontSize', 8);

    hold(ax, 'off');
end