clc
clear

T = importAndConvertIBCSV('U7293679_20240101_20241231.csv');

% Step 4: Find index for each subtable
% 2 different kinds of table (Feldname, Feldwert) and data tables
% find all lines with Header
headerIndices = find(strcmp(strtrim(T{:,2}), "Header"));
% extend so the 2. column as the end index for each table
headerIndices(:,2) = [headerIndices(2:end)-1; size(T, 1)];
% Find Header for special tables (Feldname, Feldwert)
feldnameRowIndices = find(strcmp(strtrim(T{:,3}), "Feldname"));
feldwertRowIndices = find(strcmp(strtrim(T{:,4}), "Feldwert"));
if feldnameRowIndices==feldwertRowIndices
    feldRowIndices = feldnameRowIndices;
end

[~, indices] = ismember(feldRowIndices, headerIndices(:,1));

feldRowIndices = headerIndices(indices,:);
headerIndices(indices,:) = [];


%% Create the info tables
infoTables = struct();  % Initialize struct

for i = 1:size(feldRowIndices, 1)
    startIdx = feldRowIndices(i, 1);
    endIdx = feldRowIndices(i, 2);
    
    % Get section name from first row (Col1)
    sectionName = T{startIdx, 1};
    
    % Skip first row by starting at startIdx+1
    sectionData = T(startIdx+1:endIdx, :);
    
    % Initialize containers
    names = {};
    values = {};
    
    % Process each row in section
    for row = 1:size(sectionData, 1)
        % Get current row data
        currentName = sectionData{row, 3};
        currentValue = sectionData{row, 4};
        
        % Only add if name is valid
        if ischar(currentName) || isstring(currentName)
            names{end+1} = char(currentName);
            
            % Convert string numbers to numeric
            if ischar(currentValue) || isstring(currentValue)
                numValue = str2double(currentValue);
                if ~isnan(numValue)
                    values{end+1} = numValue;
                else
                    values{end+1} = currentValue;
                end
            else
                values{end+1} = currentValue;
            end
        end
    end
    
    % Only create table if we have valid data
    if ~isempty(names)
        % Create valid field name for struct
        validFieldName = matlab.lang.makeValidName(sectionName);
        
        % Convert to column vectors
        names = names(:);
        values = values(:);
        
        % Create table with row names
        t = table(values, 'VariableNames', {'Value'});
        t.Properties.RowNames = names;
        
        % Store in struct
        infoTables.(validFieldName) = t;
    end
end

%% Create financial tables struct with complete bounds checking
finTable = struct();

for i = 1:size(headerIndices, 1)
    tempTab = T{headerIndices(i,1):headerIndices(i,2),:};
    % Assuming 'data' is your string array
    tableName = tempTab{1,1};  % Get table name from (1,1)
    columnNames = cellstr(tempTab(1,2:end));  % Get column names from row 2 (ignoring first column)
    columnNames = columnNames(~cellfun('isempty', columnNames));
    %length(columnNames)
    tableData = cellstr(tempTab(2:end,2:length(columnNames)+1));  % Get data (ignoring first column and first two rows)
    % columnNames
    % tableData

    % Create the table
    t = convertNumericStringsInTable(tableData);
    t.Properties.VariableNames = columnNames;
    %t = cell2table(tableData, 'VariableNames', columnNames);
    
    % Store in a struct with the table name
    % Create subtables for Transaktion Aktien, Devisen etc. 
    if strcmp(tableName, 'Transaktionen')
        subtableName = tempTab{2,4};
        finTable.(matlab.lang.makeValidName(tableName)). ...
            (matlab.lang.makeValidName(subtableName)) = t;
    elseif strcmp(tableName, 'Nettovermoegenswert') & width(t)==2
        infoTables.(matlab.lang.makeValidName(tableName)) = t;
    else
        finTable.(matlab.lang.makeValidName(tableName)) = t;
    end

end


%% 
function T = convertNumericStringsInTable(T_cell)
% 
% 
    T_numeric = cellfun(@str2double, T_cell);
    is_numeric_text = ~isnan(T_numeric);
    T_cell(is_numeric_text) = num2cell(T_numeric(is_numeric_text));
    % conert [] to NaNs
    T_cell = replaceEmptyCharWithNaNInNumericColumns(T_cell);
    % convert dates to datetime;
    T_cell = autoConvertDatesInCellArray(T_cell);
    
    T = array2table(T_cell);
    T = flattenDatetimeColumns(T);
% 
end

function C_out = replaceEmptyCharWithNaNInNumericColumns(C_in)
% Replace [] and 0×0 char with NaN only in clearly numeric columns

    C_out = C_in;
    [nRows, nCols] = size(C_in);

    for col = 1:nCols
        vals = C_in(:, col);

        % Heuristic: treat column as numeric if >70% values are numeric
        isNumFlags = cellfun(@(x) isnumeric(x) && ~isempty(x), vals);
        isNonEmpty = ~cellfun(@isempty, vals);
        ratio = sum(isNumFlags) / max(1, sum(isNonEmpty));

        isNumericColumn = ratio >= 0.7;

        if isNumericColumn
            for row = 1:nRows
                val = C_out{row, col};
                if isempty(val) && ~(ischar(val) && ~isempty(val)) && ~isstring(val)
                    C_out{row, col} = NaN;
                end
            end
        end
    end
end


function C_out = autoConvertDatesInCellArray(C_in)
% Detects and converts date or datetime strings to datetime (wrapped in {})
% Supports formats: 'yyyy-MM-dd' and 'yyyy-MM-dd, HH:mm:ss'

    C_out = C_in;
    [nRows, nCols] = size(C_in);

    for col = 1:nCols
        colVals = C_in(:, col);
        sampleVals = strings(nRows, 1);
        detectedFormat = "";
        isValid = false(nRows, 1);

        % Try to detect format
        for row = 1:nRows
            val = colVals{row};
            if ischar(val) || isstring(val)
                str = strtrim(string(val));
                if strlength(str) >= 10 && contains(str, '-')
                    sampleVals(row) = str;

                    % Attempt to parse with known formats
                    try
                        if contains(str, ',')  % datetime with time
                            datetime(str, 'InputFormat', 'yyyy-MM-dd, HH:mm:ss');
                            detectedFormat = 'yyyy-MM-dd, HH:mm:ss';
                        else  % date only
                            datetime(str, 'InputFormat', 'yyyy-MM-dd');
                            detectedFormat = 'yyyy-MM-dd';
                        end
                        isValid(row) = true;
                    catch
                        % not valid
                    end
                end
            end
        end

        % Proceed only if majority of non-empty entries are valid
        nonEmpty = sampleVals ~= "";
        if sum(isValid) / max(1, sum(nonEmpty)) >= 0.7 && detectedFormat ~= ""
            % Use placeholder for invalids
            sampleVals(~isValid) = "1900-01-01";

            % Convert
            try
                dtCol = datetime(sampleVals, 'InputFormat', detectedFormat);
                dtCol(dtCol == datetime(1900,1,1)) = NaT;

                % Wrap in cells
                C_out(:, col) = num2cell(dtCol);
            catch
                warning("Column %d failed datetime conversion.", col);
            end
        end
    end
end



function T_out = flattenDatetimeColumns(T_in)
% Converts columns of 1x1 datetime cells into proper datetime columns

    T_out = T_in;

    for col = 1:width(T_out)
        colData = T_out{:, col};

        if iscell(colData)
            allDatetime = all(cellfun(@(x) isa(x, 'datetime'), colData));
            if allDatetime
                T_out.(col) = vertcat(colData{:});
            end
        end
    end
end

function T = importAndConvertIBCSV(filename)
    % IMPORTANDCONVERTIBCSV_2  Reads and processes an IB CSV file into a clean table
    %   T = importAndConvertIBCSV_2(filename)
    %
    %   Steps:
    %   - Reads UTF-8 encoded file
    %   - Removes outer quote pairs
    %   - Merges split cells inside quoted strings
    %   - Splits lines by comma, preserving empty cells
    %   - Converts numeric text to double
    %   - Returns cleaned table as cell due to mixed strings/numeric data

    % Read file as lines
    fid = fopen(filename, 'r', 'n', 'UTF-8');
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    raw = raw{1};
    % Correct for german Umlaute
    raw = cellfun(@(x) regexprep(x, {'ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß'},...
    {'ae', 'oe', 'ue','Ae', 'Oe', 'Ue', 'ss'}), ...
            raw, 'UniformOutput', false);

    % Remove leading/trailing quote pairs in lines
    quotePos = strfind(raw, '"');
    idx = find(~cellfun(@isempty, quotePos) & cellfun(@(v) any(v == 1), quotePos));

    longIdx = cellfun(@(v) numel(v) > 2, quotePos(idx));
    quotePos(idx(longIdx)) = cellfun(@(v) v([1 end]), quotePos(idx(longIdx)), 'UniformOutput', false);

    for i = idx'
        str = raw{i};
        pos = quotePos{i};
        pos(pos > strlength(str)) = [];
        pos = sort(pos, 'descend');
        for p = pos
            str(p) = [];
        end
        raw{i} = str;
    end

    % Remove trailing semicolons
    raw = cellfun(@(s) regexprep(s, ';$', ''), raw, 'UniformOutput', false);

    % Split rows by comma (keeps empty fields)
    rows = cellfun(@(s) split(string(s), ',')', raw, 'UniformOutput', false);
    maxCols = max(cellfun(@numel, rows));

    % Pad rows to have equal length
    rowsPadded = cellfun(@(r) [r, repmat("", 1, maxCols - numel(r))], ...
                         rows, 'UniformOutput', false);

    % Merge cells wrapped in quotes (spanning multiple commas)
    cleanedRows = cell(size(rowsPadded));
    for i = 1:numel(rowsPadded)
        row = rowsPadded{i};
        merged = [];
        j = 1;
        while j <= numel(row)
            cellStr = row(j);
            if startsWith(cellStr, '"') && ~endsWith(cellStr, '"')
                mergedStr = cellStr;
                j = j + 1;
                while j <= numel(row)
                    mergedStr = mergedStr + "," + row(j);
                    if endsWith(strtrim(row(j)), '"')
                        break;
                    end
                    j = j + 1;
                end
                merged = [merged, mergedStr];
                j = j + 1;
            else
                merged = [merged, cellStr];
                j = j + 1;
            end
        end
        merged(end+1:maxCols) = "";  % pad right if needed
        cleanedRows{i} = merged;
    end

    % Convert to table
    T = array2table(vertcat(cleanedRows{:}));

    % Remove remaining quotes
    T = varfun(@(x) replace(x, '"', ""), T);

    % % Convert numeric-looking strings to actual doubles
    % T_cell = table2cell(T);
    % T_numeric = cellfun(@str2double, T_cell);
    % is_numeric_text = ~isnan(T_numeric);
    % T_cell(is_numeric_text) = num2cell(T_numeric(is_numeric_text));
    % 
    % T = array2table(T_cell);
end











