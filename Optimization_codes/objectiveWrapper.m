function cost = objectiveWrapper(designStruct, missionFcn, archFcn, penaltyWeight)
%OBJECTIVEWRAPPER  Turns mission evaluation output into a scalar PSO cost.
%
%   cost = objectiveWrapper(designStruct, missionFcn, archFcn, penaltyWeight)
%
%   missionFcn : function handle with signature
%                  [endurance_s, g] = missionFcn(designStruct, archFcn)
%                where g is a vector of constraint violations (g(i) <= 0
%                means satisfied; g(i) > 0 means violated by that amount).
%                See evaluateMission_stub.m for the reference implementation
%                you'll replace with real Module 1/2/3 physics.
%
%   archFcn    : function handle to the TEAM'S power-sharing architecture
%                (see exampleArchitecture.m for the required interface).
%                Passed straight through to missionFcn -- this wrapper and
%                pso.m never need to know what's inside it.
%
%   penaltyWeight : scalar weight on the quadratic exterior penalty. Raise
%                   this if PSO keeps returning infeasible designs; lower
%                   it if the search gets stuck refusing to explore near
%                   the constraint boundary.
%
%   We are maximizing endurance, and PSO is a minimizer, so:
%     cost = -endurance + penaltyWeight * sum(max(0, g).^2)
%
%   Note: this function is already O(1) per call (a single missionFcn call
%   plus a vectorized penalty sum) -- the real cost of an optimization run
%   lives inside missionFcn, not here. No algorithmic change was needed;
%   only a defensive shape check was added below so a malformed g from a
%   custom missionFcn fails fast with a clear message instead of silently
%   producing the wrong cost.

[endurance_s, g] = missionFcn(designStruct, archFcn);

if ~isvector(g)
    error('objectiveWrapper:badConstraintShape', ...
        'missionFcn must return g as a vector of constraint violations.');
end

violation = sum(max(0, g).^2);
cost = -endurance_s + penaltyWeight * violation;

end
