function cleanTable = extractFromCellTable(cellTable)
% EXTRACTFROMCELLTABLE Extracts values from cell-wrapped columns while preserving types
%   cleanTable = extractFromCellTable(cellTable) processes a table where
%   columns contain cell arrays of proper types and extracts the values.

    % Validate input
    if ~istable(cellTable)
        error('Input must be a table');
    end
    
    cleanTable = table();
    vars = cellTable.Properties.VariableNames;
    
    for i = 1:numel(vars)
        colData = cellTable.(vars{i});
        
        if ~iscell(colData)
            cleanTable.(vars{i}) = colData;
            continue;
        end
        
        % Find first non-empty cell (safer implementation)
        nonEmptyIdx = find(~cellfun('isempty', colData), 1);
        
        if isempty(nonEmptyIdx)
            % Entire column is empty - default to double NaN
            cleanTable.(vars{i}) = NaN(size(colData));
            continue;
        end
        
        sample = colData{nonEmptyIdx};
        
        if isdatetime(sample)
            % Datetime handling
            cleanTable.(vars{i}) = cellfun(@(x) ifelse(isempty(x), NaT, x), colData);
        elseif isnumeric(sample)
            % Numeric handling
            cleanTable.(vars{i}) = cellfun(@(x) ifelse(isempty(x), NaN, x), colData);
        elseif ischar(sample) || isstring(sample)
            % Text handling
            strCol = string(colData);
            strCol(cellfun('isempty', colData)) = missing;
            cleanTable.(vars{i}) = strCol;
        else
            % Fallback - keep as cell array
            cleanTable.(vars{i}) = colData;
        end
    end
end

% Helper function
function out = ifelse(condition, trueVal, falseVal)
    out = repmat(trueVal, size(condition));
    out(~condition) = falseVal(~condition);
end
