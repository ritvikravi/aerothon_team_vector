function plotEngineOperatingMap(bestDesign, archFcn)
% PLOTENGINEOPERATINGMAP Generates a non-linear engine SFC curve 
% and overlays the mission operating points selected by the optimizer.

% Generate SFC Curve
throttle_range = linspace(0.05, 1.0, 100);
SFC_nominal = 0.32; % kg/kWh base
SFC_curve = SFC_nominal * (0.7 + 0.25./throttle_range + 0.05*throttle_range.^2);

% Retrieve operating points from best design
phases = {'takeoff', 'climb', 'cruise', 'loiter', 'descent'};
% Corresponding physical required powers in kW
P_req = [55, 45, 20, 15, 5]; 

throttle_points = zeros(1, 5);
SFC_points = zeros(1, 5);

missionState = struct('altitude_m', 0, 'speed_mps', 0, 'powerRequired_W', 0, 'batterySoC', 1.0);

for i = 1:5
    pShare = archFcn(bestDesign, phases{i}, missionState);
    P_engine_kW = P_req(i) * (1 - pShare);

    tau = min(max(P_engine_kW / bestDesign.engineSize_kW, 0.05), 1.0);
    throttle_points(i) = tau;
    SFC_points(i) = SFC_nominal * (0.7 + 0.25/tau + 0.05*tau^2);
end

figure('Name', 'Engine Efficiency Map', 'Position', [200, 200, 850, 500], 'Color', 'w');
plot(throttle_range * 100, SFC_curve, 'LineWidth', 2.5, 'Color', '#0072BD');
hold on;

% Plot and label each phase operating point
colors = {'#D95319', '#EDB120', '#7E2F8E', '#77AC30', '#4DBEEE'};
for i = 1:5
    plot(throttle_points(i)*100, SFC_points(i), 'o', 'MarkerSize', 10, ...
        'MarkerFaceColor', colors{i}, 'MarkerEdgeColor', 'k', 'LineWidth', 1.5);
    text(throttle_points(i)*100 + 2, SFC_points(i), phases{i}, ...
        'FontSize', 10, 'FontWeight', 'bold');
end

xlabel('Engine Throttle Setting (%)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Specific Fuel Consumption (kg/kWh)', 'FontSize', 12, 'FontWeight', 'bold');
title('Turboshaft SFC Map & Optimized Operational Points', 'FontSize', 14, 'FontWeight', 'bold');
grid on;
xlim([0, 110]);
legend('Theoretical Engine SFC Curve', 'Optimized Operating Points', 'Location', 'northeast');
end