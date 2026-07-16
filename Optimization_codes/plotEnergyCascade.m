function plotEnergyCascade(bestDesign, phaseName)
% PLOTENERGYCASCADE Generates a scientific power cascade diagram
% illustrating the energy path and losses from storage to aerodynamics.

% Fetch phase-specific powers for takeoff (high power) as an example
% In a real pipeline, extract this directly from the evaluateMission run.
P_fuel_input = 150;     % kW (Chemical fuel power input)
P_battery_input = 45;   % kW (Electrical battery power output)

% Losses
Eng_thermal_loss = P_fuel_input * 0.68; % 32% thermal efficiency
Motor_elec_loss = P_battery_input * 0.10; % 90% electrical efficiency

P_shaft_mech = (P_fuel_input - Eng_thermal_loss) + (P_battery_input - Motor_elec_loss);
Prop_slip_loss = P_shaft_mech * 0.15; % 85% propeller efficiency

P_thrust = P_shaft_mech - Prop_slip_loss;
Drag_induced = P_thrust * 0.40; % 40% of thrust fights induced drag
Drag_parasitic = P_thrust * 0.60; % 60% fights parasitic drag

% Data for waterfall/cascade representation
values = [P_fuel_input + P_battery_input, ...
    -Eng_thermal_loss, ...
    -Motor_elec_loss, ...
    -Prop_slip_loss, ...
    -Drag_induced, ...
    -Drag_parasitic];

labels = {'Total Source Power', 'Engine Thermal Loss', 'Motor/ESC Loss', ...
    'Propeller Slip Loss', 'Induced Drag Loss', 'Parasitic Drag'};

cumulative = cumsum([0, values(1:end-1)]);

figure('Name', 'Thermodynamic Cascade', 'Position', [150, 150, 850, 500], 'Color', 'w');

for i = 1:numel(values)
    if values(i) >= 0
        color = '#77AC30'; % Green for source
    else
        color = '#D95319'; % Red for losses
    end
    rectangle('Position', [i-0.4, cumulative(i) + min(values(i),0), 0.8, abs(values(i))], ...
        'FaceColor', color, 'EdgeColor', 'k', 'LineWidth', 1.2);
    hold on;
    text(i, cumulative(i) + values(i)/2, sprintf('%.1f kW', abs(values(i))), ...
        'HorizontalAlignment', 'center', 'Color', 'w', 'FontWeight', 'bold');
end

set(gca, 'XTick', 1:numel(labels), 'XTickLabel', labels, 'XTickLabelRotation', 15);
ylabel('Power Level (kW)', 'FontSize', 12, 'FontWeight', 'bold');
title(sprintf('Thermodynamic and Aerodynamic Power Cascade (%s Phase)', upper(phaseName)), ...
    'FontSize', 14, 'FontWeight', 'bold');
grid on;
ylim([0, max(cumulative)*1.1]);
end