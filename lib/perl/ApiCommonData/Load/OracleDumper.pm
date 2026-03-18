package ApiCommonData::Load::OracleDumper;

use strict;
use DBI;
use Scalar::Util qw(looks_like_number);
use Exporter qw(import);

our @EXPORT_OK = qw(dumpOracleSchema);

=pod

=head2 ApiCommonData::Load::OracleDumper

=over 4

=item Description

Module to dump Oracle schemas to CSV files

=item Usage

use ApiCommonData::Load::OracleDumper qw(dumpOracleSchema);

dumpOracleSchema($instance, $dbuser, $dbpass, $target_schema, $output_dir);

=back

=cut

=head2 dumpOracleSchema

Dumps specified tables from an Oracle schema to CSV files with header rows.
Tables are dumped in the order provided to maintain foreign key dependencies.
Uses comma as field delimiter and backtick as quote character.

Parameters:
  $instance      - Oracle database instance
  $dbuser        - Database username
  $dbpass        - Database password
  $target_schema - Schema name to dump
  $output_dir    - Output directory for CSV files
  $tables        - Arrayref of table names in topologically sorted order

Returns: 1 on success, dies on error

=cut

sub dumpOracleSchema {
    my ($instance, $dbuser, $dbpass, $target_schema, $output_dir, $tables) = @_;

    die "dumpOracleSchema: tables parameter is required\n" unless $tables && ref($tables) eq 'ARRAY';
    die "dumpOracleSchema: output_dir parameter is required\n" unless $output_dir;

    # Build DSN
    my $dsn = "dbi:Oracle:$instance";
    $ENV{'NLS_LANG'} = ".AL32UTF8";

    # Connect to Oracle
    my $dbh = DBI->connect($dsn, $dbuser, $dbpass, {
        RaiseError => 1,
        AutoCommit => 0,
        LongReadLen => 50000000,
    }) or die $DBI::errstr;

    $dbh->do("ALTER SESSION SET NLS_TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS'") || die "FAILED";
    $dbh->do("ALTER SESSION SET NLS_TIMESTAMP_TZ_FORMAT = 'YYYY-MM-DD HH24:MI:SS TZH:TZM'") || die "FAILED";

    # Dump tables in the order provided
    foreach my $table_name (@$tables) {
      my $output_file = "$output_dir/$table_name.csv";

        if (-e $output_file) {
            print "Found file: $table_name.csv\n";
            next;
        }

        print "Exporting table: $table_name\n";

        my $sql = _getTableSql($target_schema, $table_name);

        my $data_sth = $dbh->prepare($sql);
        $data_sth->execute();

        # Column names
        my @columns = @{$data_sth->{NAME}};

        # Open file
        open my $fh, ">:utf8", $output_file or die "Cannot open $output_file: $!";
        binmode(STDOUT, ":utf8");

        # Print header
        print $fh join(",", map { "$_" } @columns), "\n";

        # Print rows
        while (my $row = $data_sth->fetchrow_arrayref) {
            my @escaped = map {
                looks_like_number($_) ? $_ : (defined $_ ? "`" . _escape($_) . "`" : '')
            } @$row;
            print $fh join(",", @escaped), "\n";
        }

        close $fh;
        $data_sth->finish;
    }

    $dbh->disconnect;

    print "All tables exported successfully.\n";

    return 1;
}

# Get custom SQL for specific tables or default SELECT *
sub _getTableSql {
    my ($target_schema, $table_name) = @_;

    my $projIdCol = "CASE WHEN project_id = 'EuPathDB' THEN 'UniDB' ELSE project_id END AS project_id";

    # Table-specific SQL queries to select only needed columns
    my %table_sql = (
        'DATASETS' => "SELECT DATASET_ID, USER_ID, DATASET_NAME, DATASET_SIZE, CONTENT_CHECKSUM, CREATED_TIME, UPLOAD_FILE, PARSER FROM $target_schema.datasets",

        'USER_BASKETS' => "SELECT basket_id, user_id, basket_name, $projIdCol, record_class, pk_column_1, pk_column_2, pk_column_3 FROM $target_schema.user_baskets",

        'PREFERENCES' => "SELECT user_id, $projIdCol, preference_name, preference_value FROM $target_schema.preferences where project_id != 'UniDB'",

        'FAVORITES' => "SELECT favorite_id, user_id, $projIdCol, record_class, pk_column_1, pk_column_2, pk_column_3, record_note, record_group, is_deleted FROM $target_schema.favorites",

        'EXTERNAL_DATABASES' => "SELECT external_database_id, external_database_name, external_database_version FROM $target_schema.external_databases",

        'LOCATIONS' => "SELECT comment_id, location_id, location_start, location_end, coordinate_type, is_reverse FROM $target_schema.locations",

        'DATASET_VALUES' => "SELECT dataset_value_id, dataset_id, dataset_value_order, data1, data2, data3, data4, data5, data6, data7 FROM $target_schema.dataset_values",

        'STEPS' => "SELECT step_id, user_id, left_child_id, right_child_id, create_time, last_run_time, estimate_size, custom_name, is_deleted, is_valid, collapsed_name, is_collapsible, assigned_weight, $projIdCol, project_version, question_name, strategy_id, display_params, display_prefs, branch_is_expanded, branch_name FROM $target_schema.steps",

        'STRATEGIES' => "SELECT strategy_id, user_id, root_step_id, $projIdCol, version, is_saved, create_time, last_view_time, last_modify_time, description, signature, name, saved_name, is_deleted, is_public FROM $target_schema.strategies WHERE root_step_id IN (SELECT step_id FROM $target_schema.steps)",

        'STEP_ANALYSIS' => "SELECT analysis_id, step_id, display_name, user_notes, is_new AS revision_status, has_params, invalid_step_reason, context_hash, context, properties FROM $target_schema.step_analysis",

        'ACCOUNT_PROPERTIES' => "SELECT user_id, key, value FROM $target_schema.account_properties WHERE user_id IN (SELECT user_id FROM $target_schema.accounts)",

        # Multi-BLAST tables with digest columns (prepend \x for PostgreSQL BYTEA hex format)
        'MULTIBLAST_JOBS' => "SELECT '\\x' || job_digest AS job_digest, job_config, query, queue_id, $projIdCol, status, created_on, delete_on FROM $target_schema.multiblast_jobs",

        'MULTIBLAST_JOB_TO_TARGETS' => "SELECT '\\x' || job_digest AS job_digest, organism, target_file FROM $target_schema.multiblast_job_to_targets",

        'MULTIBLAST_JOB_TO_JOBS' => "SELECT '\\x' || job_digest AS job_digest, '\\x' || parent_digest AS parent_digest, position FROM $target_schema.multiblast_job_to_jobs",

        'MULTIBLAST_USERS' => "SELECT '\\x' || job_digest AS job_digest, user_id, description, max_download_size, run_directly FROM $target_schema.multiblast_users",

        'MULTIBLAST_FMT_JOBS' => "SELECT '\\x' || report_digest AS report_digest, '\\x' || job_digest AS job_digest, status, config, queue_id, created_on FROM $target_schema.multiblast_fmt_jobs",

        'MULTIBLAST_USERS_TO_FMT_JOBS' => "SELECT '\\x' || report_digest AS report_digest, user_id, description FROM $target_schema.multiblast_users_to_fmt_jobs",
    );

    # Return custom SQL if defined, otherwise default SELECT *
    return $table_sql{$table_name} || "SELECT * FROM $target_schema.$table_name";
}

# Escape backticks and remove problematic characters
sub _escape {
    my $val = shift;
    $val =~ s/\x00//g;      # remove null ascii characters that break pg COPY
    $val =~ s/`/``/g;       # Escape backticks
    $val =~ s/\r?\n/ /g;    # Remove newlines
    $val =~ s/\x{FFFF}//g;  # remove unicode noncharacter
    return $val;
}

1;
