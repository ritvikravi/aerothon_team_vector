function plotDesignSpace(varSpec, bestDesign, history, missionFcn, archFcn)
% PLOTDESIGNSPACE Generates a 3D contour map of the design space
% with the optimized solution and constraint boundaries highlighted.

fprintf('Generating 3D Design Space Landscape (this may take a moment)... \n');

% Define Grid over variables: Engine Size vs Battery Capacity
engineGrid = linspace(varSpec(1).lb, varSpec(1).ub, 30);
batteryGrid = linspace(varSpec(2).lb, varSpec(2).ub, 30);
[Eng, Bat] = meshgrid(engineGrid, batteryGrid);
Cost = zeros(size(Eng));
Feasible = true(size(Eng));

% Copy best design as a baseline for other variables (like splits)
tempDesign = bestDesign;
penaltyWeight = 100;

for r = 1:size(Eng, 1)
    for c = 1:size(Eng, 2)
        tempDesign.engineSize_kW = Eng(r,c);
        tempDesign.batteryCap_kWh = Bat(r,c);

        % Evaluate mission
        [endurance_s, g] = missionFcn(tempDesign, archFcn);
        violation = sum(max(0, g).^2);
        Cost(r,c) = -endurance_s + penaltyWeight * violation;

        % Check feasibility
        if any(g > 0)
            Feasible(r,c) = false;
        end
    end
end

% Convert Cost back to positive Endurance (Hours) for intuitive reading
Endurance_hours = -Cost / 3600;
% For highly infeasible points, cap the negative values for clean plotting
Endurance_hours(Endurance_hours < -1) = -1; 

% --- Plotting ---
figure('Name', 'Scientific Sizing Landscape', 'Position', [100, 100, 900, 700], 'Color', 'w');

% 3D Surface
surf(Eng, Bat, Endurance_hours, 'EdgeColor', 'none', 'FaceAlpha', 0.85);
colormap(gca, parula(100));
colorbar;
hold on;

% Highlight Infeasible Region Contour
contour3(Eng, Bat, double(Feasible)*5, 1, 'r-', 'LineWidth', 2); 

% Plot the Optimum Point
plot3(bestDesign.engineSize_kW, bestDesign.batteryCap_kWh, -bestDesign.bestFval/3600 + 0.1, ...
    'm*', 'MarkerSize', 15, 'LineWidth', 3);

% Labels & Styling
xlabel('Turboshaft Engine Size (kW)', 'FontSize', 12, 'FontWeight', 'bold');
ylabel('Battery Capacity (kWh)', 'FontSize', 12, 'FontWeight', 'bold');
zlabel('Effective Objective (Endurance, Hours)', 'FontSize', 12, 'FontWeight', 'bold');
title('3D Sizing Landscape & Constraint Boundary', 'FontSize', 14, 'FontWeight', 'bold');
legend('Endurance Surface (Hours)', 'Constraint Boundary (g_i = 0)', 'Global Optimum (PSO)', ...
    'Location', 'northeast');

view(-45, 30);
grid on;
shading interp;
camlight;
lighting phong;
end