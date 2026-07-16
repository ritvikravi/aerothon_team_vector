function pShare = exampleArchitecture(designStruct, phaseName, missionState)
%EXAMPLEARCHITECTURE Dynamic parallel-hybrid architecture driven by PSO.

switch phaseName
    case 'takeoff'
        pShare = designStruct.split_takeoff;
    case 'climb'
        pShare = designStruct.split_climb;
    case 'cruise'
        pShare = designStruct.split_cruise;
    case 'loiter'
        pShare = designStruct.split_loiter;
    case 'descent'
        pShare = designStruct.split_descent;
    otherwise
        pShare = 0.0;
end

% Hard safety override: Protect the battery reserve
if missionState.batterySoC < 0.20
    pShare = 0.0; % Force engine-only if battery is dangerously low
end

end