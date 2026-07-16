function varSpec = designVectorSpec()
%DESIGNVECTORSPEC  Design variables for the propulsion sizing problem.

varSpec = struct('name', {}, 'lb', {}, 'ub', {}, 'type', {});

% Hardware Sizing
varSpec(end+1) = struct('name','engineSize_kW',   'lb',20, 'ub',150, 'type','continuous');
varSpec(end+1) = struct('name','batteryCap_kWh',  'lb',5,  'ub',60,  'type','continuous');
varSpec(end+1) = struct('name','numMotors',       'lb',1,  'ub',4,   'type','integer');

% Hybrid Architecture Power Splits (Optimizer decides how much electric power to use!)
varSpec(end+1) = struct('name','split_takeoff', 'lb',0, 'ub',1, 'type','continuous');
varSpec(end+1) = struct('name','split_climb',   'lb',0, 'ub',1, 'type','continuous');
varSpec(end+1) = struct('name','split_cruise',  'lb',0, 'ub',1, 'type','continuous');
varSpec(end+1) = struct('name','split_loiter',  'lb',0, 'ub',1, 'type','continuous');
varSpec(end+1) = struct('name','split_descent', 'lb',0, 'ub',1, 'type','continuous');

end