-- This file and its contents are licensed under the Timescale License.
-- Please see the included NOTICE for copyright information and
-- LICENSE-TIMESCALE for a copy of the license.

-- Disable background workers since we are testing manual refresh
\c :TEST_DBNAME :ROLE_SUPERUSER
SELECT _timescaledb_internal.stop_background_workers();
SET ROLE :ROLE_DEFAULT_PERM_USER;

CREATE TABLE conditions (time timestamptz NOT NULL, device int, temp float);
SELECT create_hypertable('conditions', 'time');

SELECT setseed(.12);

INSERT INTO conditions
SELECT t, ceil(abs(timestamp_hash(t::timestamp))%4)::int, abs(timestamp_hash(t::timestamp))%40
FROM generate_series('2020-05-01', '2020-05-05', '10 minutes'::interval) t;

-- Show the most recent data
SELECT * FROM conditions
ORDER BY time DESC, device
LIMIT 10;

CREATE VIEW daily_temp
WITH (timescaledb.continuous,
      timescaledb.materialized_only=true)
AS
SELECT time_bucket('1 day', time) AS day, device, avg(temp) AS avg_temp
FROM conditions
GROUP BY 1,2;

-- The continuous aggregate should be empty
SELECT * FROM daily_temp
ORDER BY day DESC, device;

-- Refresh the most recent few days:
CALL refresh_continuous_aggregate('daily_temp', '2020-05-03', '2020-05-05');

SELECT * FROM daily_temp
ORDER BY day DESC, device;

-- Refresh the rest
CALL refresh_continuous_aggregate('daily_temp', '2020-05-01', '2020-05-03');

-- Compare the aggregate to the equivalent query on the source table
SELECT * FROM daily_temp
ORDER BY day DESC, device;

SELECT time_bucket('1 day', time) AS day, device, avg(temp) AS avg_temp
FROM conditions
GROUP BY 1,2
ORDER BY 1 DESC,2;

-- Test unusual, but valid input
CALL refresh_continuous_aggregate('daily_temp', '2020-05-01'::timestamptz, '2020-05-03'::date);
CALL refresh_continuous_aggregate('daily_temp', '2020-05-01'::date, '2020-05-03'::date);
CALL refresh_continuous_aggregate('daily_temp', 0, '2020-05-01');

-- Unbounded window forward in time
\set ON_ERROR_STOP 0
-- Currently doesn't work due to timestamp overflow bug in a query optimization
CALL refresh_continuous_aggregate('daily_temp', '2020-05-03', NULL);
CALL refresh_continuous_aggregate('daily_temp', NULL, NULL);
\set ON_ERROR_STOP 1

-- Unbounded window back in time
CALL refresh_continuous_aggregate('daily_temp', NULL, '2020-05-01');

-- Test bad input
\set ON_ERROR_STOP 0
-- Bad continuous aggregate name
CALL refresh_continuous_aggregate(NULL, '2020-05-03', '2020-05-05');
CALL refresh_continuous_aggregate('xyz', '2020-05-03', '2020-05-05');
-- Valid object, but not a continuous aggregate
CALL refresh_continuous_aggregate('conditions', '2020-05-03', '2020-05-05');
-- Object ID with no object
CALL refresh_continuous_aggregate(1, '2020-05-03', '2020-05-05');
-- Lacking arguments
CALL refresh_continuous_aggregate('daily_temp');
CALL refresh_continuous_aggregate('daily_temp', '2020-05-03');
-- Bad time ranges
CALL refresh_continuous_aggregate('daily_temp', 'xyz', '2020-05-05');
CALL refresh_continuous_aggregate('daily_temp', '2020-05-03', 'xyz');
CALL refresh_continuous_aggregate('daily_temp', '2020-05-03', '2020-05-01');
CALL refresh_continuous_aggregate('daily_temp', '2020-05-03', '2020-05-03');
-- Bad time input
CALL refresh_continuous_aggregate('daily_temp', '2020-05-01'::text, '2020-05-03'::text);

\set ON_ERROR_STOP 1

-- Test different time types
CREATE TABLE conditions_date (time date NOT NULL, device int, temp float);
SELECT create_hypertable('conditions_date', 'time');

CREATE VIEW daily_temp_date
WITH (timescaledb.continuous,
      timescaledb.materialized_only=true)
AS
SELECT time_bucket('1 day', time) AS day, device, avg(temp) AS avg_temp
FROM conditions_date
GROUP BY 1,2;

CALL refresh_continuous_aggregate('daily_temp_date', '2020-05-01', '2020-05-03');

-- Test smallint-based continuous aggregate
CREATE TABLE conditions_smallint (time smallint NOT NULL, device int, temp float);
SELECT create_hypertable('conditions_smallint', 'time', chunk_time_interval => 20);

INSERT INTO conditions_smallint
SELECT t, ceil(abs(timestamp_hash(to_timestamp(t)::timestamp))%4)::smallint, abs(timestamp_hash(to_timestamp(t)::timestamp))%40
FROM generate_series(1, 100, 1) t;

CREATE OR REPLACE FUNCTION smallint_now()
RETURNS smallint LANGUAGE SQL STABLE AS
$$
    SELECT coalesce(max(time), 0)::smallint
    FROM conditions_smallint
$$;

SELECT set_integer_now_func('conditions_smallint', 'smallint_now');

CREATE VIEW cond_20_smallint
WITH (timescaledb.continuous,
      timescaledb.materialized_only=true)
AS
SELECT time_bucket(SMALLINT '20', time) AS bucket, device, avg(temp) AS avg_temp
FROM conditions_smallint c
GROUP BY 1,2;

CALL refresh_continuous_aggregate('cond_20_smallint', 5, 50);

SELECT * FROM cond_20_smallint
ORDER BY 1,2;

-- Test int-based continuous aggregate
CREATE TABLE conditions_int (time int NOT NULL, device int, temp float);
SELECT create_hypertable('conditions_int', 'time', chunk_time_interval => 20);

INSERT INTO conditions_int
SELECT t, ceil(abs(timestamp_hash(to_timestamp(t)::timestamp))%4)::int, abs(timestamp_hash(to_timestamp(t)::timestamp))%40
FROM generate_series(1, 100, 1) t;

CREATE OR REPLACE FUNCTION int_now()
RETURNS int LANGUAGE SQL STABLE AS
$$
    SELECT coalesce(max(time), 0)
    FROM conditions_int
$$;

SELECT set_integer_now_func('conditions_int', 'int_now');

CREATE VIEW cond_20_int
WITH (timescaledb.continuous,
      timescaledb.materialized_only=true)
AS
SELECT time_bucket(INT '20', time) AS bucket, device, avg(temp) AS avg_temp
FROM conditions_int
GROUP BY 1,2;

CALL refresh_continuous_aggregate('cond_20_int', 5, 50);

SELECT * FROM cond_20_int
ORDER BY 1,2;

-- Test bigint-based continuous aggregate
CREATE TABLE conditions_bigint (time bigint NOT NULL, device int, temp float);
SELECT create_hypertable('conditions_bigint', 'time', chunk_time_interval => 20);

INSERT INTO conditions_bigint
SELECT t, ceil(abs(timestamp_hash(to_timestamp(t)::timestamp))%4)::bigint, abs(timestamp_hash(to_timestamp(t)::timestamp))%40
FROM generate_series(1, 100, 1) t;

CREATE OR REPLACE FUNCTION bigint_now()
RETURNS bigint LANGUAGE SQL STABLE AS
$$
    SELECT coalesce(max(time), 0)::bigint
    FROM conditions_bigint
$$;

SELECT set_integer_now_func('conditions_bigint', 'bigint_now');

CREATE VIEW cond_20_bigint
WITH (timescaledb.continuous,
      timescaledb.materialized_only=true)
AS
SELECT time_bucket(BIGINT '20', time) AS bucket, device, avg(temp) AS avg_temp
FROM conditions_bigint
GROUP BY 1,2;

CALL refresh_continuous_aggregate('cond_20_bigint', 5, 50);

SELECT * FROM cond_20_bigint
ORDER BY 1,2;
