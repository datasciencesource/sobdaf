from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col,
    trim,
    when,
    isnan,
    sum as spark_sum,
)
from pyspark import StorageLevel

import os
import time
import threading
import subprocess

try:
    import psutil
except ImportError:
    psutil = None


# =========================
# Configuration
# =========================
HDFS_INPUT_PATH = "hdfs:///sobdaf/part-*"
HDFS_STORAGE_PATH = "/sobdaf"

# Use True for CSV files containing column headers.
# Use False for headerless Sqoop output and verify the column order below.
CSV_HAS_HEADER = True

HEADERLESS_COLUMNS = [
    "id",
    "product_id",
    "purchasing_price",
    "quantity",
    "stock_date",
]

MYSQL_URL = (
    "jdbc:mysql://127.0.0.1:3306/dbtest"
    "?useSSL=false&serverTimezone=UTC"
)
MYSQL_TABLE = "product_quantity"
MYSQL_USER = "usertest"
MYSQL_PASSWORD = os.environ.get("MYSQL_PASSWORD", "Admin1111")
MYSQL_DRIVER = "com.mysql.cj.jdbc.Driver"

REQUIRED_COLUMNS = ["product_id", "quantity"]


# =========================
# Resource monitoring
# =========================
cpu_samples = []
memory_samples = []
monitor_errors = []
stop_monitor = threading.Event()


def monitor_resources():
    """Measure whole-machine utilization, not Spark-only utilization."""
    if psutil is None:
        return

    try:
        psutil.cpu_percent(interval=None)

        while not stop_monitor.wait(0.5):
            cpu_samples.append(psutil.cpu_percent(interval=None))
            memory_samples.append(psutil.virtual_memory().percent)

    except Exception as exc:
        monitor_errors.append(str(exc))


def get_hdfs_storage_gib(path):
    """Return logical HDFS storage in GiB, excluding replication."""
    try:
        output = subprocess.check_output(
            ["hdfs", "dfs", "-du", "-s", path],
            text=True,
            stderr=subprocess.PIPE,
            timeout=30,
        )
        size_bytes = int(output.split()[0])
        return size_bytes / (1024 ** 3)

    except Exception as exc:
        print(f"HDFS storage measurement unavailable: {exc}")
        return None


def average_or_none(samples):
    return sum(samples) / len(samples) if samples else None


def format_metric(value, decimals=2):
    return "N/A" if value is None else f"{value:.{decimals}f}"


def count_condition(condition, name):
    return spark_sum(
        when(condition, 1).otherwise(0)
    ).alias(name)


# =========================
# Main workflow
# =========================
spark = None
result = None
monitor_thread = None

try:
    spark = (
        SparkSession.builder
        .appName("SOBDAF_HDFSToMySQL_DataQuality")
        .getOrCreate()
    )

    # Spark startup and prior ingestion are outside this measurement.
    workflow_start = time.perf_counter()

    monitor_thread = threading.Thread(
        target=monitor_resources,
        daemon=True,
    )
    monitor_thread.start()

    # =========================
    # Read CSV data from HDFS
    # =========================
    processing_start = time.perf_counter()

    df = (
        spark.read
        .option("header", str(CSV_HAS_HEADER).lower())
        .option("inferSchema", "false")
        .option("sep", ",")
        .option("mode", "FAILFAST")
        .csv(HDFS_INPUT_PATH)
    )

    if not CSV_HAS_HEADER:
        if len(df.columns) != len(HEADERLESS_COLUMNS):
            raise ValueError(
                f"Expected {len(HEADERLESS_COLUMNS)} CSV columns, "
                f"but found {len(df.columns)}. "
                "Check HEADERLESS_COLUMNS and the input format."
            )

        df = df.toDF(*HEADERLESS_COLUMNS)

    missing_columns = [
        name for name in REQUIRED_COLUMNS
        if name not in df.columns
    ]

    if missing_columns:
        raise ValueError(
            f"Required columns are absent: {missing_columns}. "
            f"Available columns: {df.columns}. "
            "If the input is headerless Sqoop output, "
            "set CSV_HAS_HEADER = False."
        )

    # Normalize blank analytical fields to null.
    prepared = df.select([
        when(
            col(name).isNull()
            | (trim(col(name).cast("string")) == ""),
            None,
        )
        .otherwise(trim(col(name).cast("string")))
        .alias(name)
        for name in REQUIRED_COLUMNS
    ])

    # Preserve the raw quantity to distinguish missing from invalid values.
    result = (
        prepared.selectExpr(
            "product_id",
            "quantity AS quantity_raw",
            "try_cast(quantity AS DOUBLE) AS quantity",
        )
        .persist(StorageLevel.MEMORY_AND_DISK)
    )

    record_count = result.count()

    if record_count == 0:
        raise ValueError(
            "The input dataset is empty. "
            "No export was performed; quality rates are undefined."
        )

    # =========================
    # Completeness and validation
    # =========================
    product_missing = col("product_id").isNull()
    quantity_missing = col("quantity_raw").isNull()

    invalid_quantity = (
        col("quantity_raw").isNotNull()
        & (
            col("quantity").isNull()
            | isnan(col("quantity"))
            | (col("quantity") == float("inf"))
            | (col("quantity") == float("-inf"))
            | (col("quantity") < 0)
        )
    )

    inconsistent_record = (
        product_missing
        | quantity_missing
        | invalid_quantity
    )

    quality = result.agg(
        count_condition(product_missing, "missing_product_id"),
        count_condition(quantity_missing, "missing_quantity"),
        count_condition(invalid_quantity, "invalid_quantity"),
        count_condition(inconsistent_record, "inconsistent_records"),
    ).first().asDict()

    total_missing_values = (
        quality["missing_product_id"]
        + quality["missing_quantity"]
    )

    # Cell-based missingness across the two selected analytical columns.
    evaluated_cells = record_count * len(REQUIRED_COLUMNS)
    missing_value_rate = (
        total_missing_values / evaluated_cells
    ) * 100

    data_consistent = quality["inconsistent_records"] == 0
    data_processing_time = time.perf_counter() - processing_start

    print("\n=== Input Validation ===")
    print(f"HDFS input: {HDFS_INPUT_PATH}")
    print("Required fields present: Yes")
    print(f"Input records: {record_count}")
    print(f"Evaluated cells: {evaluated_cells}")
    print(
        f"Missing product_id values: "
        f"{quality['missing_product_id']}"
    )
    print(
        f"Missing quantity values: "
        f"{quality['missing_quantity']}"
    )
    print(
        f"Invalid nonmissing quantity values: "
        f"{quality['invalid_quantity']}"
    )
    print(
        f"Records failing validation: "
        f"{quality['inconsistent_records']}"
    )
    print(f"Missing-value rate (%): {missing_value_rate:.2f}")

    if not data_consistent:
        raise ValueError(
            "Input failed completeness or quantity validation. "
            "The MySQL destination was not overwritten."
        )

    # Select fields without aggregation: one output row per input row.
    curated = result.select("product_id", "quantity")

    # =========================
    # Export to MySQL
    # =========================
    jdbc_options = {
        "url": MYSQL_URL,
        "dbtable": MYSQL_TABLE,
        "user": MYSQL_USER,
        "password": MYSQL_PASSWORD,
        "driver": MYSQL_DRIVER,
    }

    export_start = time.perf_counter()

    # Replaces the existing destination table.
    (
        curated.write
        .format("jdbc")
        .options(**jdbc_options)
        .mode("overwrite")
        .save()
    )

    export_end = time.perf_counter()

    processing_export_time = export_end - workflow_start
    export_time = export_end - export_start

    stop_monitor.set()
    monitor_thread.join()

    # =========================
    # Verify exported record count
    # =========================
    verification_start = time.perf_counter()

    local_db_df = (
        spark.read
        .format("jdbc")
        .options(**jdbc_options)
        .load()
    )

    local_db_record_count = local_db_df.count()
    verification_time = time.perf_counter() - verification_start

    counts_match = record_count == local_db_record_count

    export_mismatch_rate = (
        abs(record_count - local_db_record_count) / record_count
    ) * 100

    overall_data_quality_score = 100 - (
        missing_value_rate + export_mismatch_rate
    ) / 2

    suitable_for_analysis = data_consistent and counts_match

    stage_throughput = (
        record_count / processing_export_time
        if processing_export_time > 0
        else None
    )

    avg_cpu_usage = average_or_none(cpu_samples)
    avg_memory_usage = average_or_none(memory_samples)

    storage_gib = get_hdfs_storage_gib(HDFS_STORAGE_PATH)

    # =========================
    # Performance results
    # =========================
    print("\n=== Instrument 1: Performance Metrics ===")
    print(
        "Data processing and validation time (seconds): "
        f"{data_processing_time:.2f}"
    )
    print(f"MySQL export time (seconds): {export_time:.2f}")
    print(
        "Processing and export workflow time (seconds): "
        f"{processing_export_time:.2f}"
    )
    print(
        "Export-count verification time, measured separately (seconds): "
        f"{verification_time:.2f}"
    )
    print(
        "Processing/export throughput (records/second): "
        f"{format_metric(stage_throughput)}"
    )
    print("Ingestion time: Not measured by this script")
    print("End-to-end pipeline time and throughput: Not calculated")

    print("\n=== Instrument 1: Resource Utilization ===")
    print(
        "Average whole-machine CPU utilization (%): "
        f"{format_metric(avg_cpu_usage)}"
    )
    print(
        "Average whole-machine memory utilization (%): "
        f"{format_metric(avg_memory_usage)}"
    )
    print(f"CPU samples: {len(cpu_samples)}")
    print(f"Memory samples: {len(memory_samples)}")
    print(
        f"HDFS logical storage for {HDFS_STORAGE_PATH} "
        f"(GiB, excluding replication): "
        f"{format_metric(storage_gib, 4)}"
    )

    if psutil is None:
        print("Resource monitoring unavailable: install psutil.")

    if monitor_errors:
        print(
            "Resource monitoring errors:",
            "; ".join(monitor_errors),
        )

    # =========================
    # Data-quality results
    # =========================
    print("\n=== Instrument 2: Data Quality ===")
    print("Required fields present: Yes")
    print(f"Number of missing cells: {total_missing_values}")
    print(
        "Data satisfies the applied validation rules: "
        f"{'Yes' if data_consistent else 'No'}"
    )
    print(f"Curated records prepared from HDFS: {record_count}")
    print(f"Exported MySQL records: {local_db_record_count}")
    print(
        "Record-count correspondence: "
        f"{'Matched' if counts_match else 'Not matched'}"
    )
    print(
        "Suitable under the applied validation and count checks: "
        f"{'Yes' if suitable_for_analysis else 'No'}"
    )
    print(f"Missing-value rate (%): {missing_value_rate:.2f}")
    print(
        "Export-count mismatch rate (%): "
        f"{export_mismatch_rate:.2f}"
    )
    print(
        "Overall data quality score (%): "
        f"{overall_data_quality_score:.2f}"
    )
    print(
        "Quality score covers missingness and export-count mismatch only."
    )
    print(
        "Export verification checks counts, not identical record contents."
    )

    if not counts_match:
        raise RuntimeError(
            "Export completed, but destination record count differs."
        )

    print(
        f"\nExecution status: Successful. "
        f"Data exported to dbtest.{MYSQL_TABLE}"
    )

except Exception as exc:
    print("\nExecution status: Failed")
    print(f"Error: {exc}")
    raise

finally:
    stop_monitor.set()

    if monitor_thread is not None:
        monitor_thread.join()

    # Stop Spark even if releasing the cached data fails.
    try:
        if result is not None:
            result.unpersist()
    finally:
        if spark is not None:
            spark.stop()
