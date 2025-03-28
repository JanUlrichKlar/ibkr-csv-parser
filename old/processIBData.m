function [infoTables, finTable] = processIBData(filename)
% PROCESSIBDATA Processes Interactive Brokers CSV data into structured tables
%   [infoTables, finTable] = processIBData(filename) imports and processes
%   an IB CSV file into two structures:
%   - infoTables: Contains metadata tables (Feldname/Feldwert sections)
%   - finTable: Contains financial transaction tables

%% Initial Setup


% Import and convert the CSV file
T = importAndConvertIBCSV(filename);

%% Step 1: Identify Table Sections
% Find all header rows that mark the start of tables
headerIndices = find(strcmp(strtrim(T{:,2}), "Header"));
headerIndices(:,2) = [headerIndices(2:end)-1; size(T, 1)]; % Add end indices

% Find special metadata tables (Feldname/Feldwert sections)
feldnameRows = find(strcmp(strtrim(T{:,3}), "Feldname"));
feldwertRows = find(strcmp(strtrim(T{:,4}), "Feldwert"));

% Validate and process metadata table indices
if feldnameRows == feldwertRows
    feldRowIndices = headerIndices(ismember(headerIndices(:,1), feldnameRows), :);
    headerIndices(ismember(headerIndices(:,1), feldnameRows), :) = []; % Remove from main headers
end

%% Step 2: Process Metadata Tables (Feldname/Feldwert)
infoTables = struct();

for i = 1:size(feldRowIndices, 1)
    startIdx = feldRowIndices(i, 1);
    endIdx = feldRowIndices(i, 2);
    
    % Get section name and data
    sectionName = T{startIdx, 1};
    sectionData = T(startIdx+1:endIdx, :);
    
    % Initialize containers
    names = {};
    values = {};
    
    % Process each row in section
    for row = 1:size(sectionData, 1)
        currentName = sectionData{row, 3};
        currentValue = sectionData{row, 4};
        
        if ischar(currentName) || isstring(currentName)
            % Store name
            names{end+1} = char(currentName);
            
            % Convert numeric strings to numbers
            if ischar(currentValue) || isstring(currentValue)
                numValue = str2double(currentValue);
                values{end+1} = ifelse(~isnan(numValue), numValue, currentValue);
            else
                values{end+1} = currentValue;
            end
        end
    end
    
    % Create table if valid data exists
    if ~isempty(names)
        validName = matlab.lang.makeValidName(sectionName);
        infoTables.(validName) = table(values(:), 'VariableNames', {'Value'}, ...
                                      'RowNames', names(:));
    end
end

%% Step 3: Process Financial Tables
finTable = struct();

for i = 1:size(headerIndices, 1)
    % Extract table segment
    tempTab = T{headerIndices(i,1):headerIndices(i,2), :};
    tableName = tempTab{1,1};
    columnNames = cleanColumnNames(tempTab(1,2:end));
    tableData = tempTab(2:end, 2:length(columnNames)+1);
    
    % Convert and clean table data
    t = convertAndCleanTable(tableData, columnNames);
    
    % Organize by table type
    if strcmp(tableName, 'Transaktionen')
        subtableName = matlab.lang.makeValidName(tempTab{2,4});
        finTable.Transaktionen.(subtableName) = t;
    elseif strcmp(tableName, 'Nettovermoegenswert') && width(t) == 2
        infoTables.Nettovermoegenswert = t;
    else
        finTable.(matlab.lang.makeValidName(tableName)) = t;
    end
end

%% Helper Functions
    function t = convertAndCleanTable(data, colNames)
        % CONVERTANDCLEANTABLE Processes raw table data
        data = convertNumericCells(data);
        data = handleEmptyCells(data);
        data = convertDateCells(data);
        t = array2table(data, 'VariableNames', colNames);
        t = flattenDatetimeColumns(t);
    end

    function data = convertNumericCells(data)
        % CONVERTNUMERICCELLS Converts string numbers to numeric
        numData = cellfun(@str2double, data);
        isNumeric = ~isnan(numData);
        data(isNumeric) = num2cell(numData(isNumeric));
    end

    function data = handleEmptyCells(data)
        % HANDLEEMPTYCELLS Converts appropriate empty cells to NaN
        [rows, cols] = size(data);
        for c = 1:cols
            if isNumericColumn(data(:,c))
                for r = 1:rows
                    if isEmptyNumeric(data{r,c})
                        data{r,c} = NaN;
                    end
                end
            end
        end
    end

    function data = convertDateCells(data)
        % CONVERTDATECELLS Converts date strings to datetime
        [rows, cols] = size(data);
        for c = 1:cols
            if isDateColumn(data(:,c))
                for r = 1:rows
                    data{r,c} = convertToDatetime(data{r,c});
                end
            end
        end
    end

    function t = flattenDatetimeColumns(t)
        % FLATTENDATETIMECOLUMNS Converts cell datetime to direct columns
        for c = 1:width(t)
            if iscell(t{:,c}) && all(cellfun(@(x) isdatetime(x), t{:,c}))
                t{:,c} = vertcat(t{:,c}{:});
            end
        end
    end

    function result = ifelse(condition, trueVal, falseVal)
        % IFELSE Ternary operation helper
        if condition
            result = trueVal;
        else
            result = falseVal;
        end
    end

    function names = cleanColumnNames(names)
        % CLEANCOLUMNNAMES Processes raw column names
        names = cellstr(names);
        names = names(~cellfun('isempty', names));
    end

    function tf = isNumericColumn(col)
        % ISNUMERICCOLUMN Checks if column should be treated as numeric
        tf = sum(cellfun(@(x) isnumeric(x) && ~isempty(x), col)) / ...
             sum(~cellfun(@isempty, col)) >= 0.7;
    end

    function tf = isEmptyNumeric(val)
        % ISEMPTYNUMERIC Checks for empty numeric cells
        tf = isnumeric(val) && isempty(val) && ...
             ~(ischar(val) && ~isempty(val)) && ~isstring(val);
    end

    function tf = isDateColumn(col)
        % ISDATECOLUMN Checks if column contains date strings
        sample = cellfun(@(x) ischar(x)||isstring(x), col);
        if sum(sample) < 0.7*length(col)
            tf = false;
            return;
        end
        % Additional date format checks would go here
        tf = true;
    end

    function dt = convertToDatetime(val)
        % CONVERTTODATETIME Converts string to datetime
        if ischar(val) || isstring(val)
            str = strtrim(string(val));
            try
                if contains(str, ',')
                    dt = datetime(str, 'InputFormat', 'yyyy-MM-dd, HH:mm:ss');
                else
                    dt = datetime(str, 'InputFormat', 'yyyy-MM-dd');
                end
            catch
                dt = val; % Return original if conversion fails
            end
        else
            dt = val;
        end
    end
end


