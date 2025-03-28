function [infoTables, finTable] = processIBKRCSV(filename)
    T = importAndConvertIBCSV(filename);

    % Find index for each subtable
    headerIndices = find(strcmp(strtrim(T{:,2}), "Header"));
    headerIndices(:,2) = [headerIndices(2:end)-1; size(T, 1)];
    
    % Detect language based on known header terms
    col3 = strtrim(string(T{:,3}));
    col4 = strtrim(string(T{:,4}));

    isGerman = any(col3 == "Feldname") && any(col4 == "Feldwert");
    isEnglish = any(col3 == "Field Name") && any(col4 == "Field Value");

    if isGerman
        fieldNameKey = "Feldname";
        fieldValueKey = "Feldwert";
        tradesLabel = "Transaktionen";
    elseif isEnglish
        fieldNameKey = "Field Name";
        fieldValueKey = "Field Value";
        tradesLabel = "Trades";
    else
        error('Unable to detect CSV language – check format.');
    end

    feldnameRowIndices = find(col3 == fieldNameKey);
    feldwertRowIndices = find(col4 == fieldValueKey);

    if feldnameRowIndices==feldwertRowIndices
        feldRowIndices = feldnameRowIndices;
    end
    [~, indices] = ismember(feldRowIndices, headerIndices(:,1));
    feldRowIndices = headerIndices(indices,:);
    headerIndices(indices,:) = [];

    % Create the info tables
    infoTables = struct();
    for i = 1:size(feldRowIndices, 1)
        startIdx = feldRowIndices(i, 1);
        endIdx = feldRowIndices(i, 2);
        sectionName = T{startIdx, 1};
        sectionData = T(startIdx+1:endIdx, :);
        names = {};
        values = {};
        for row = 1:size(sectionData, 1)
            currentName = sectionData{row, 3};
            currentValue = sectionData{row, 4};
            if ischar(currentName) || isstring(currentName)
                names{end+1} = char(currentName);
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
        if ~isempty(names)
            validFieldName = matlab.lang.makeValidName(sectionName);
            names = names(:);
            values = values(:);
            t = table(values, 'VariableNames', {'Value'});
            t.Properties.RowNames = names;
            infoTables.(validFieldName) = t;
        end
    end

    % Create financial tables
    finTable = struct();
    for i = 1:size(headerIndices, 1)
        tempTab = T{headerIndices(i,1):headerIndices(i,2),:};
        tableName = tempTab{1,1};
        columnNames = cellstr(tempTab(1,2:end));
        columnNames = columnNames(~cellfun('isempty', columnNames));
        tableData = cellstr(tempTab(2:end, 2:length(columnNames)+1));
        t = convertNumericStringsInTable(tableData);
        t.Properties.VariableNames = columnNames;
        
        if strcmp(tableName, tradesLabel)
            subtableName = tempTab{2,4};
            finTable.(matlab.lang.makeValidName(tableName)).(matlab.lang.makeValidName(subtableName)) = extractFromCellTable(t);
        else
            finTable.(matlab.lang.makeValidName(tableName)) = extractFromCellTable(t);
        end
    end

    %% Nested helper functions
    function T = convertNumericStringsInTable(T_cell)
        T_numeric = cellfun(@str2double, T_cell);
        is_numeric_text = ~isnan(T_numeric);
        T_cell(is_numeric_text) = num2cell(T_numeric(is_numeric_text));
        T_cell = replaceEmptyCharWithNaNInNumericColumns(T_cell);
        T_cell = autoConvertDatesInCellArray(T_cell);
        T = array2table(T_cell);
        T = flattenDatetimeColumns(T);
    end

    function C_out = replaceEmptyCharWithNaNInNumericColumns(C_in)
        C_out = C_in;
        [nRows, nCols] = size(C_in);
        for col = 1:nCols
            vals = C_in(:, col);
            isNumFlags = cellfun(@(x) isnumeric(x) && ~isempty(x), vals);
            isNonEmpty = ~cellfun(@isempty, vals);
            ratio = sum(isNumFlags) / max(1, sum(isNonEmpty));
            if ratio >= 0.7
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
        C_out = C_in;
        [nRows, nCols] = size(C_in);
        for col = 1:nCols
            colVals = C_in(:, col);
            sampleVals = strings(nRows, 1);
            detectedFormat = "";
            isValid = false(nRows, 1);
            for row = 1:nRows
                val = colVals{row};
                if ischar(val) || isstring(val)
                    str = strtrim(string(val));
                    if strlength(str) >= 10 && contains(str, '-')
                        sampleVals(row) = str;
                        try
                            if contains(str, ',')
                                datetime(str, 'InputFormat', 'yyyy-MM-dd, HH:mm:ss');
                                detectedFormat = 'yyyy-MM-dd, HH:mm:ss';
                            else
                                datetime(str, 'InputFormat', 'yyyy-MM-dd');
                                detectedFormat = 'yyyy-MM-dd';
                            end
                            isValid(row) = true;
                        catch
                        end
                    end
                end
            end
            nonEmpty = sampleVals ~= "";
            if sum(isValid) / max(1, sum(nonEmpty)) >= 0.7 && detectedFormat ~= ""
                sampleVals(~isValid) = "1900-01-01";
                try
                    dtCol = datetime(sampleVals, 'InputFormat', detectedFormat);
                    dtCol(dtCol == datetime(1900,1,1)) = NaT;
                    C_out(:, col) = num2cell(dtCol);
                catch
                    warning("Column %d failed datetime conversion.", col);
                end
            end
        end
    end

    function T_out = flattenDatetimeColumns(T_in)
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
        fid = fopen(filename, 'r', 'n', 'UTF-8');
        raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
        fclose(fid);
        raw = raw{1};
        raw = cellfun(@(x) regexprep(x, {'ä','ö','ü','Ä','Ö','Ü','ß'}, ...
            {'ae','oe','ue','Ae','Oe','Ue','ss'}), raw, 'UniformOutput', false);
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
        raw = cellfun(@(s) regexprep(s, ';$', ''), raw, 'UniformOutput', false);
        rows = cellfun(@(s) split(string(s), ',')', raw, 'UniformOutput', false);
        maxCols = max(cellfun(@numel, rows));
        rowsPadded = cellfun(@(r) [r, repmat("", 1, maxCols - numel(r))], rows, 'UniformOutput', false);
        cleanedRows = cell(size(rowsPadded));
        for i = 1:numel(rowsPadded)
            row = rowsPadded{i};
            merged = []; j = 1;
            while j <= numel(row)
                cellStr = row(j);
                if startsWith(cellStr, '"') && ~endsWith(cellStr, '"')
                    mergedStr = cellStr; j = j + 1;
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
            merged(end+1:maxCols) = "";
            cleanedRows{i} = merged;
        end
        T = array2table(vertcat(cleanedRows{:}));
        T = varfun(@(x) replace(x, '"', ""), T);
    end
end

function cleanTable = extractFromCellTable(cellTable)
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
        
        nonEmptyIdx = find(~cellfun('isempty', colData), 1);
        
        if isempty(nonEmptyIdx)
            cleanTable.(vars{i}) = NaN(size(colData));
            continue;
        end
        
        sample = colData{nonEmptyIdx};
        
        if isdatetime(sample)
            cleanTable.(vars{i}) = cellfun(@(x) ifelse(isempty(x), NaT, x), colData);
        elseif isnumeric(sample)
            cleanTable.(vars{i}) = cellfun(@(x) ifelse(isempty(x), NaN, x), colData);
        elseif ischar(sample) || isstring(sample)
            strCol = string(colData);
            strCol(cellfun('isempty', colData)) = missing;
            cleanTable.(vars{i}) = strCol;
        else
            cleanTable.(vars{i}) = colData;
        end
    end
end

function out = ifelse(condition, trueVal, falseVal)
    out = repmat(trueVal, size(condition));
    out(~condition) = falseVal(~condition);
end