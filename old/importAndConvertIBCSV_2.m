%function T_clean = importAndConvertIBCSV_2(filename)
clc
clear
    filename = 'U7293679_20240101_20241231.csv';
    % 1. Datei einlesen
    fid = fopen(filename, 'r', 'n', 'UTF-8');
    raw = textscan(fid, '%s', 'Delimiter', '\n', 'Whitespace', '');
    fclose(fid);
    raw = raw{1};

    quotePos = strfind(raw, '"');
    idx = find(~cellfun(@isempty, quotePos) & cellfun(@(v) any(v == 1), quotePos));

    % ggf. quotePos kürzen:
    longIdx = cellfun(@(v) numel(v) > 2, quotePos(idx));
    quotePos(idx(longIdx)) = cellfun(@(v) v([1 end]), quotePos(idx(longIdx)), 'UniformOutput', false);
    for i = idx'
        str = raw{i};
        pos = quotePos{i};
        pos(pos > strlength(str)) = [];  % Absichern, falls quotePos außerhalb der Stringlänge

        % Um mehrere Zeichen an verschiedenen Positionen zu löschen, ist es am einfachsten rückwärts zu löschen
        pos = sort(pos, 'descend');  % wichtig: rückwärts, damit Indizes beim Löschen nicht verrutschen
        for p = pos
        str(p) = [];
        end
    raw{i} = str;
    end

   raw = cellfun(@(s) regexprep(s, ';$', ''), raw, 'UniformOutput', false);
   

   % Schritt 1: Split und transponieren
rows = cellfun(@(s) split(string(s), ',')', raw, 'UniformOutput', false);

% Schritt 2: Maximale Spaltenzahl bestimmen
maxCols = max(cellfun(@numel, rows));

% Schritt 3: Horizontal auffüllen (nicht vertikal!)
rowsPadded = cellfun(@(r) [r, repmat("", 1, maxCols - numel(r))], ...
                     rows, 'UniformOutput', false);

cleanedRows = cell(size(rowsPadded));  % gleiche Größe wie Original
for i = 1:numel(rowsPadded)
    row = rowsPadded{i};
    merged = [];
    j = 1;
    while j <= numel(row)
        cellStr = row(j);
        if startsWith(cellStr, '"') && ~endsWith(cellStr, '"')
            % Beginn eines zusammengeklammerten Feldes
            mergeStart = j;
            mergeEnd = j;
            mergedStr = cellStr;
            j = j + 1;
            while j <= numel(row)
                mergedStr = mergedStr + "," + row(j);
                mergeEnd = j;
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
    
    % Auffüllen mit leeren Zellen, falls Zeile kürzer geworden ist
    merged(end+1:maxCols) = "";  % Padding rechts
    cleanedRows{i} = merged;
end

% In Tabelle umwandeln
T = array2table(vertcat(cleanedRows{:}));
T = varfun(@(x) replace(x, '"', ""), T);  % entfernt ALLE Anführungszeichen
T_cell = table2cell(T);

% apply str2double on all cells (returns NaN for those already numeric):
T_numeric = cellfun(@str2double,T_cell);
% take the non-NaN elements of C_numeric (i.e., those that were in fact
% numbers stored as chars/strings) and put them where they belong in C:
is_numeric_text = ~isnan(T_numeric);
T_cell(is_numeric_text) = num2cell(T_numeric(is_numeric_text));
T = array2table(T_cell);