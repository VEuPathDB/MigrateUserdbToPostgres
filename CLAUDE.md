# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Perl-based migration toolkit for migrating Oracle user databases to PostgreSQL. It handles two distinct database types:
- **User databases**: Contains WDK user data, comments, metrics, uploads, multiblast jobs, and EDA user data
- **Account databases**: Contains study access and user account information

The migration involves dumping Oracle schemas to CSV files, cleaning/filtering the data, and bulk loading into PostgreSQL schemas.

## Architecture

### Main Components

1. **bin/migrateUserdbToPostgres** - Main orchestration script
   - Coordinates the full migration pipeline
   - Manages multiple target schemas with different source mappings
   - Handles both 'user' and 'account' database types
   - Creates workspace structure: `dump/`, `clean/`, `load/`, `logs/`

2. **bin/dumpOracleSchemaToCsvFiles** - Oracle export utility
   - Connects to Oracle and exports all tables in a schema to CSV
   - Uses backtick (`) as field delimiter instead of comma for data fields
   - Escapes special characters and handles Unicode
   - Applies custom SQL queries for specific tables to select only needed columns

3. **bin/setUserdbSequences** - Sequence management
   - Configures PostgreSQL sequences to increment by 10 to avoid conflicts
   - Supports 'n' (north) and 's' (south) modes for different server instances
   - Calculates starting values based on existing data modulo 10

4. **lib/perl/ApiCommonData/Load/Psql.pm** - PostgreSQL loader module
   - Encapsulates `psql \COPY` command generation
   - Handles CSV format with custom delimiters and quote characters
   - Manages connection strings and log files

### Schema Mappings (User Mode)

The migration maps multiple Oracle schemas to distinct PostgreSQL schemas:

- **userlogins5** → Multiple target schemas:
  - `wdkuser`: User baskets, favorites, datasets, steps, strategies, step analysis
  - `usercomments`: Comments and related tables
  - `multiblast`: Multi-BLAST job tracking

- **announce** → `announce`: Messages and projects
- **metrics** → `metrics`: Usage statistics tables
- **uploads** → `uploads`: User file uploads
- **edauser** → `edauser`: EDA analysis data

### Schema Mappings (Account Mode)

- **studyaccess** → `studyaccess`: Staff, providers, end users
- **useraccounts** → `useraccounts`: Accounts, properties, subscriptions

### Required Source Code Repositories

The migration scripts depend on DDL files from multiple repositories that must be checked out in `$sourceCodeDir`:

- WDK
- MetricReports
- ApiCommonData
- service-multi-blast
- service-eda
- OAuth2Server

## Usage

### Migrate User Database
```bash
bin/migrateUserdbToPostgres user <sourcecode_dir> <workspace_dir> <dbuser> <dbpass> <oracle_instance> <pg_database> <pg_host> [createSchemas]
```

### Migrate Account Database
```bash
bin/migrateUserdbToPostgres account <sourcecode_dir> <workspace_dir> <dbuser> <dbpass> <oracle_instance> <pg_database> <pg_host> [createSchemas]
```

### Set PostgreSQL Sequences
```bash
bin/setUserdbSequences user|account n|s <dbuser> <dbpass> <pg_database> <pg_host> [doit]
```
- `n|s`: 'n' for north server (remainder 0), 's' for south server (remainder 3)
- `doit`: Optional flag to actually execute the ALTER SEQUENCE commands

### Dump Oracle Schema
```bash
bin/dumpOracleSchemaToCsvFiles <oracle_instance> <dbuser> <dbpass> <schema_name>
```

## Data Cleaning Strategy

The `clean/` directory contains symlinks to only the tables specified in `tablesToKeep` for each schema. This allows selective migration of tables from multi-purpose Oracle schemas. Tables not in the keep list are dumped but not loaded.

## CSV Format Details

- Field delimiter in CSV data: `,` (comma for fields in header and data rows)
- String quote character: `` ` `` (backtick) for non-numeric values
- Escaped characters: Backticks doubled, newlines removed, null bytes removed
- Null representation: Empty string
- Character encoding: UTF8/AL32UTF8
- Header row: Column names without quotes

## Database Connection Details

- Oracle: Uses DBI with DSN format `dbi:Oracle:<instance>`
- PostgreSQL: Uses DBI with DSN format `dbi:Pg:dbname=<db>;host=<host>;port=5432`
- PostgreSQL loading: Uses `psql` command-line tool with `\COPY` command
