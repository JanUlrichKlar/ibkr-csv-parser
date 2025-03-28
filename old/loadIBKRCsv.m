function data = loadIBKRCsv(filename)
    % Read file content
    fid = fopen(filename, 'r', 'n', 'UTF-8');
    rawText = fread(fid, '*char')';
    fclose(fid);
    
    % Remove BOM if present
    if startsWith(rawText, char(65279))
        rawText = rawText(2:end);
    end
    
    % Normalize line endings and split into lines
    lines = strsplit(regexprep(rawText, '\r\n|\r', '\n'), '\n')';
    lines(cellfun(@isempty, lines)) = []; % Remove empty lines
    
    % Process each line to clean quotes
    cleanedLines = cell(size(lines));
    for i = 1:length(lines)
        % Remove all double quotes (replace with single quotes if needed)
        cleanedLines{i} = regexprep(lines{i}, '"+', '');
    end
    
    cleanedLines
    % Convert to table (assuming first line is header)
    data = cell2table(cell(length(cleanedLines)-1, 1), 'VariableNames', {'RawData'});
    
    % If you want to split into columns (comma-separated)
    if ~isempty(cleanedLines)
        splitData = cellfun(@(x) strsplit(x, ','), cleanedLines, 'UniformOutput', false);
        numCols = max(cellfun(@length, splitData));
        
        % Create table with consistent columns
        tableData = cell(length(splitData), numCols);
        for i = 1:length(splitData)
            tableData(i, 1:length(splitData{i})) = splitData{i};
        end
        
        data = cell2table(tableData(2:end, :), 'VariableNames', tableData(1, :));
    end
end

