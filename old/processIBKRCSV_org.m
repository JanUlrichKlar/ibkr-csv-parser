function [infoTables, finTable] = processIBKRCSV(filename)
    T = importAndConvertIBCSV(filename);

    % Find index for each subtable
    headerIndices = find(strcmp(strtrim(T{:,2}), "Header"));
    headerIndices(:,2) = [headerIndices(2:end)-1; size(T, 1)];
    feldnameRowIndices = find(strcmp(strtrim(T{:,3}), "Feldname"));
    feldwertRowIndices = find(strcmp(strtrim(T{:,4}), "Feldwert"));
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
        if strcmp(tableName, 'Transaktionen')
            subtableName = tempTab{2,4};
            finTable.(matlab.lang.makeValidName(tableName)).(matlab.lang.makeValidName(subtableName)) = t;
        elseif strcmp(tableName, 'Nettovermoegenswert') & width(t)==2
            infoTables.(matlab.lang.makeValidName(tableName)) = t;
        else
            finTable.(matlab.lang.makeValidName(tableName)) = t;
        end
    end

    %% Nested helpers (exact same as original)
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


