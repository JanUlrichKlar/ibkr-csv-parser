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



