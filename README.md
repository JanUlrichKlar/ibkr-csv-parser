# processIBKRCSV

This MATLAB function processes CSV account statements exported from **Interactive Brokers (IBKR)**. It supports both **English** and **German** report formats and returns structured tables containing metadata and financial data.

## Features

- ✅ Automatically detects report language (EN/DE)
- ✅ Parses IBKR CSV exports and extracts:
  - Account information
  - Trade history
  - Dividends, fees, interest, and more
- ✅ Handles European special characters and complex quoting
- ✅ Converts numeric strings and date strings into appropriate MATLAB types

## Requirements

- MATLAB R2020b or newer (some features may work in older versions)
- No external toolboxes required

## Usage

```matlab
[infoTables, finTable] = processIBKRCSV('path/to/your_ibkr_report.csv');
