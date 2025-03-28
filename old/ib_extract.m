clc
clear

%% 1. Load csv
% data = readtable('U7293679_20220102_20221230.csv','ReadVariableNames', false);
% opts = detectImportOptions('U7293679_20220102_20221230.csv');
% opts.VariableNamesLine = 0; % No header
% opts.DataLines = [2 Inf];   % Skip first line if needed
% opts.MissingRule = 'omitrow'; % Skip missing data
% data = readtable('U7293679_20220102_20221230.csv', opts);

% Read the file as raw text
fid = fopen('U7293679_20220102_20221230.csv', 'r');
data = textscan(fid, '%s', 'Delimiter', '\n');
fclose(fid);
data = cell2table(data{1});



% Correct for german Umlaute
data.Var1 = cellfun(@(x) regexprep(x, {'ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß'},...
    {'ae', 'oe', 'ue','Ae', 'Oe', 'Ue', 'ss'}), ...
            data.Var1, 'UniformOutput', false);

% Step 1: Convert to string array and remove semicolons
data.Var1 = string(data.Var1);
cleanStrings = strip(data.Var1, 'right', ';');

% Step 2: Process each line to handle multiple quoted commas
% timestamps have commas inside their string
% To split into table replace commas in timestamp with marker @
% then create table and replace marker @ with comma again.
numRows = length(cleanStrings);
splitData = cell(numRows, 1);

for i = 1:numRows
    line = cleanStrings(i);
    
    % Find all text inside quotes
    quotedParts = regexp(line, '"(.*?)"', 'tokens');
    
    % Temporarily replace commas in quoted sections
    protected = line;
    for j = 1:length(quotedParts)
        quotedText = quotedParts{j}{1};
        protectedQuoted = strrep(quotedText, ',', '@'); % Replace ALL commas
        protected = strrep(protected, ['"' quotedText '"'], ['"' protectedQuoted '"']);
    end
    
    % Now safely split at commas
    parts = split(protected, ',');
    
    % Restore original commas in quoted sections
    parts = strrep(parts, '@', ',');
    
    splitData{i} = parts;
end

% Step 3: Pad to uniform size and create table
maxCols = max(cellfun(@numel, splitData));
paddedData = cellfun(@(x) [x; strings(maxCols - numel(x), 1)], splitData, 'UniformOutput', false);
resultMatrix = [paddedData{:}]';
resultTable = array2table(resultMatrix, 'VariableNames', compose('Col%d', 1:maxCols));
resultTable = convertTableStringsToNumbers(resultTable);

%% 


%%
% Step 4: Find index for each subtable
% 2 different kinds of table (Feldname, Feldwert) and data tables
% find all lines with Header
headerIndices = find(resultTable.Col2 == "Header");
% extend so the 2. column as the end index for each table
headerIndices(:,2) = [headerIndices(2:end)-1; size(resultTable, 1)];
% Find Header for special tables (Feldname, Feldwert)
feldnameRowIndices = find(resultTable.Col3 == "Feldname");
feldwertRowIndices = find(resultTable.Col4 == "Feldwert");
if feldnameRowIndices==feldwertRowIndices
    feldRowIndices = feldnameRowIndices;
end

[~, indices] = ismember(feldRowIndices, headerIndices(:,1));

feldRowIndices = headerIndices(indices,:);
headerIndices(indices,:) = [];

%headerRowIndices = setdiff(headerRowIndices, feldRowIndices);


%% Create the info tables
infoTables = struct();  % Initialize struct

for i = 1:size(feldRowIndices, 1)
    startIdx = feldRowIndices(i, 1);
    endIdx = feldRowIndices(i, 2);
    
    % Get section name from first row (Col1)
    sectionName = resultTable{startIdx, 1};
    
    % Skip first row by starting at startIdx+1
    sectionData = resultTable(startIdx+1:endIdx, :);
    
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
    tempTab = resultTable{headerIndices(i,1):headerIndices(i,2),:};
    % Assuming 'data' is your string array
    tableName = tempTab{1,1};  % Get table name from (1,1)
    columnNames = cellstr(tempTab(1,2:end));  % Get column names from row 2 (ignoring first column)
    columnNames = columnNames(~cellfun('isempty', columnNames));
    %length(columnNames)
    tableData = cellstr(tempTab(2:end,2:length(columnNames)+1));  % Get data (ignoring first column and first two rows)
    % columnNames
    % tableData

    % Create the table
    t = cell2table(tableData, 'VariableNames', columnNames);
   
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

function T_converted = convertTableStringsToNumbers(T)
    % Erstelle leere Zell-Tabelle mit gleichen Spaltennamen
    C = cell(size(T));
    T_converted = cell2table(C, 'VariableNames', T.Properties.VariableNames);

    for col = 1:width(T)
        for row = 1:height(T)
            raw = T{row, col};

            % Umwandlung zu string (robust gegen char/string)
            if ismissing(raw)
                T_converted{row, col} = {""};  % leere Zelle mit leerem String
                continue;
            end

            str = strtrim(string(raw));

            if str == ""
                T_converted{row, col} = {""};
                continue;
            end

            % Versuch numerischer Konvertierung
            num = str2double(str);
            if ~isnan(num) && ~strcmpi(str, "NaN")
                T_converted{row, col} = {num};  % Zahl als Zellinhalt
            else
                T_converted{row, col} = {char(str)};  % char-String als Zellinhalt
            end
        end
    end
end

