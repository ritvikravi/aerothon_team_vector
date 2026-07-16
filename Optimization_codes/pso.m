function [bestDesign, bestFval, history] = pso(objFcn, varSpec, opts)
%PSO  Generic, modular Particle Swarm Optimizer for mixed-variable design problems.
%
%   [bestDesign, bestFval, history] = pso(objFcn, varSpec, opts)
%
%   objFcn   : function handle, objFcn(designStruct) -> scalar cost (MINIMIZED).
%              Wrap your real objective + constraint penalties inside this
%              handle (see objectiveWrapper.m) -- pso.m only ever sees a
%              scalar number back.
%
%   varSpec  : struct array, one entry per design variable:
%                .name  (string) - field name used in designStruct
%                .lb    (double) - lower bound
%                .ub    (double) - upper bound
%                .type  (string) - 'continuous' | 'integer' | 'categorical'
%              For 'categorical', treat lb=1, ub=numel(options); decode the
%              resulting integer index to your real option list inside your
%              own module (see designVectorSpec.m for the pattern).
%              Add or remove entries freely -- pso.m never hardcodes variable
%              count or order, so growing the design vector (e.g. adding more
%              power-sharing-architecture parameters) needs no change here.
%
%   opts     : struct, all fields optional (defaults shown):
%                .swarmSize     = 40
%                .maxIter       = 150
%                .w0            = 0.9   % initial inertia weight
%                .wMin          = 0.4   % final inertia weight (linear decay)
%                .c1            = 1.5   % cognitive coefficient
%                .c2            = 1.5   % social coefficient
%                .vMaxFrac      = 0.2   % max velocity, as fraction of range
%                .tolFun        = 1e-6  % min improvement to reset stall count
%                .stallIterMax  = 20    % stop after this many stalled iters
%                .seed          = []    % RNG seed, for reproducible runs
%                .verbose       = true
%                .useParallel   = false % evaluate the swarm with parfor if
%                                        % the Parallel Computing Toolbox is
%                                        % available (falls back to a plain
%                                        % for-loop otherwise). Worthwhile
%                                        % once objFcn (i.e. your real
%                                        % Module 1/2/3 pipeline) is
%                                        % expensive; pure overhead for the
%                                        % cheap stub evaluator.
%
%   bestDesign : decoded struct of the best design found (fields = varSpec names)
%   bestFval   : best (minimum) objective value found
%   history    : struct with .bestFval per iteration, for convergence plots
%
%   This is a population-based metaheuristic, NOT a brute-force grid search:
%   cost scales with (swarmSize x maxIter) objective evaluations, not with
%   the size of the design space. Adding more design variables (e.g. more
%   architecture parameters) does not blow up the search cost the way a
%   grid search would.

if nargin < 3, opts = struct(); end
opts = setDefault(opts, 'swarmSize', 40);
opts = setDefault(opts, 'maxIter', 150);
opts = setDefault(opts, 'w0', 0.9);
opts = setDefault(opts, 'wMin', 0.4);
opts = setDefault(opts, 'c1', 1.5);
opts = setDefault(opts, 'c2', 1.5);
opts = setDefault(opts, 'vMaxFrac', 0.2);
opts = setDefault(opts, 'tolFun', 1e-6);
opts = setDefault(opts, 'stallIterMax', 20);
opts = setDefault(opts, 'seed', []);
opts = setDefault(opts, 'verbose', true);
opts = setDefault(opts, 'useParallel', false);

if ~isempty(opts.seed)
    rng(opts.seed);
end

nVars = numel(varSpec);
lb = [varSpec.lb];
ub = [varSpec.ub];
range = ub - lb;
vMax = opts.vMaxFrac * range;

% Precompute which columns are integer/categorical ONCE. The original code
% re-ran strcmp against every column on every repair/decode call (i.e.
% swarmSize*maxIter*2 times); the type of a variable never changes during
% a run, so this mask is computed a single time and reused everywhere.
isDiscrete = strcmp({varSpec.type}, 'integer') | strcmp({varSpec.type}, 'categorical');
fieldNames = {varSpec.name}';   % cached once for fast struct decoding

useParallel = opts.useParallel && hasParallelPool();
if opts.useParallel && ~useParallel && opts.verbose
    fprintf('useParallel requested but Parallel Computing Toolbox/pool not available -- running serially.\n');
end

nP = opts.swarmSize;
X = lb + rand(nP, nVars) .* range;
X = repairVector(X, isDiscrete, lb, ub);
V = -vMax + 2*vMax .* rand(nP, nVars);

fVal = evaluateSwarm(X, objFcn, fieldNames, isDiscrete, useParallel);
pBestX = X;
pBestF = fVal;
[gBestF, idx] = min(pBestF);
gBestX = pBestX(idx,:);

history.bestFval = zeros(opts.maxIter,1);
stallCount = 0;
lastIter = opts.maxIter;

for iter = 1:opts.maxIter
    w = opts.w0 - (opts.w0 - opts.wMin) * (iter/opts.maxIter);

    r1 = rand(nP, nVars);
    r2 = rand(nP, nVars);
    V = w.*V + opts.c1.*r1.*(pBestX - X) + opts.c2.*r2.*(gBestX - X);
    V = max(min(V, vMax), -vMax);

    X = X + V;
    X = max(min(X, ub), lb);
    X = repairVector(X, isDiscrete, lb, ub);

    fVal = evaluateSwarm(X, objFcn, fieldNames, isDiscrete, useParallel);
    improved = fVal < pBestF;
    pBestF(improved) = fVal(improved);
    pBestX(improved,:) = X(improved,:);

    [bestNow, idx] = min(pBestF);
    if bestNow < gBestF - opts.tolFun
        gBestF = bestNow;
        gBestX = pBestX(idx,:);
        stallCount = 0;
    else
        stallCount = stallCount + 1;
    end

    history.bestFval(iter) = gBestF;

    if opts.verbose && (mod(iter,10)==0 || iter==1)
        fprintf('Iter %3d | best cost = %.4f | stall = %d\n', iter, gBestF, stallCount);
    end

    if stallCount >= opts.stallIterMax
        if opts.verbose
            fprintf('Converged: no improvement for %d iterations.\n', stallCount);
        end
        lastIter = iter;
        break;
    end
end

history.bestFval = history.bestFval(1:lastIter);
bestDesign = decodeDesignVector(gBestX, fieldNames, isDiscrete);
bestFval = gBestF;

end

% ---------------------------------------------------------------- local --
function opts = setDefault(opts, field, value)
if ~isfield(opts, field) || isempty(opts.(field))
    opts.(field) = value;
end
end

function tf = hasParallelPool()
% Cheap, dependency-free check for whether parfor can actually be used.
tf = false;
try
    tf = license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
catch
    tf = false;
end
end

function fVal = evaluateSwarm(X, objFcn, fieldNames, isDiscrete, useParallel)
% Evaluate the objective for every particle. Kept as its own function so
% the serial/parallel choice is made in exactly one place.
nP = size(X,1);
fVal = zeros(nP,1);
if useParallel
    parfor i = 1:nP
        fVal(i) = objFcn(decodeDesignVector(X(i,:), fieldNames, isDiscrete)); %#ok<PFBNS>
    end
else
    for i = 1:nP
        fVal(i) = objFcn(decodeDesignVector(X(i,:), fieldNames, isDiscrete));
    end
end
end

function X = repairVector(X, isDiscrete, lb, ub)
% Round integer/categorical columns to the nearest valid integer.
% Vectorized: operates on all discrete columns at once instead of looping
% column-by-column with a strcmp check on every call.
if any(isDiscrete)
    Xd = round(X(:,isDiscrete));
    Xd = max(min(Xd, ub(isDiscrete)), lb(isDiscrete));
    X(:,isDiscrete) = Xd;
end
end

function s = decodeDesignVector(x, fieldNames, isDiscrete)
% Turn a raw numeric row vector into a named struct, so objective/mission
% functions can refer to designStruct.<name> instead of column indices.
% Rounding mask and field names are precomputed once by the caller instead
% of being recomputed on every single decode call.
x(isDiscrete) = round(x(isDiscrete));
s = cell2struct(num2cell(x(:)), fieldNames, 1);
end
