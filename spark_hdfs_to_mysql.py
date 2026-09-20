from pyspark.sql import SparkSession
from pyspark.sql.functions import sum as spark_sum

# 1. Start Spark
spark = (
    SparkSession.builder
    .appName("SOBDAF")
    .master("local[*]")
    .getOrCreate()
)

spark.sparkContext.setLogLevel("ERROR")

# 2. Define the five columns in the HDFS files
schema = """
    id INT,
    product_id INT,
    purchasing_price DOUBLE,
    quantity DOUBLE,
    stock_date TIMESTAMP
"""

# 3. Read comma-separated data from HDFS (no header)
data = (
    spark.read
    .schema(schema)
    .option("header", "false")
    .option("timestampFormat", "yyyy-MM-dd HH:mm:ss.S")
    .option("mode", "FAILFAST")
    .csv("hdfs:///sobdaf/part*")
)

# 4. Calculate total quantity for each product
result = data.groupBy("product_id").agg(
    spark_sum("quantity").alias("total_quantity")
)

result.show()

# 5. Save results to local MySQL
result.coalesce(1).write.jdbc(
    url=(
        "jdbc:mysql://127.0.0.1:3306/dbtest"
        "?useSSL=false&allowPublicKeyRetrieval=true"
        "&serverTimezone=UTC"
    ),
    table="product_quantity",
    mode="overwrite",
    properties={
        "user": "usertest",
        "password": "Admin1111",
        "driver": "com.mysql.cj.jdbc.Driver"
    }
)

print("Results saved to dbtest.product_quantity")

# 6. Stop Spark
spark.stop()
