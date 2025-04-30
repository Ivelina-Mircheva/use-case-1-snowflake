-- Направете си нова база данни, наречена ECOMERSE_DB.
CREATE DATABASE SPARROW_ECOMERSE_DB;

CREATE SCHEMA SPARROW_ECOMERSE_DB.orders_management;
CREATE STAGE SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders;

LIST @SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders

SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13 FROM @ecomerse_orders

--Копирайте данните от файл, в Snowflake таблица с име по избор.
CREATE TABLE td_orders
AS
SELECT $1 AS order_id, $2 AS customer_id, $3 AS customer_name,$4 AS order_date,  
$5 AS product, $6 AS quantity,$7 AS price,$8 AS discount,$9 AS total_amount, 
$10 AS payment_method, $11 AS shipping_address, $12 AS code, $13 AS Status
FROM @SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders/ecommerce_orders.csv
WHERE 1 = 2

SELECT * FROM td_orders;
DELETE FROM td_orders;

-- COPY into td_orders
COPY INTO td_orders
FROM (
SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13 FROM
@SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders/ecommerce_orders.csv
)
FILE_FORMAT = (
TYPE = CSV, SKIP_HEADER = 1
)
FORCE = TRUE

-- Ако Адреса за доставка липсва, но статуса е Delivered - прехвърлете записа към отделна таблица, която да съдържа само и единствено такива доставки, готови за ревю, td_for_review

SELECT * FROM td_orders WHERE SHIPPING_ADDRESS IS NULL AND (CODE='Delivered' OR STATUS='Delivered')

CREATE TABLE td_for_review
AS
SELECT $1 AS order_id, $2 AS customer_id, $3 AS customer_name,$4 AS order_date,  
$5 AS product, $6 AS quantity,$7 AS price,$8 AS discount,$9 AS total_amount, 
$10 AS payment_method, $11 AS shipping_address, $12 AS wrong_data, $13 AS Status
FROM @SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders/ecommerce_orders.csv
WHERE 1 = 2

SELECT * FROM td_for_review;
-------------------
INSERT INTO td_for_review(ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, ORDER_DATE, PRODUCT, QUANTITY, PRICE,
DISCOUNT, TOTAL_AMOUNT, PAYMENT_METHOD, SHIPPING_ADDRESS, WRONG_DATA, STATUS)
SELECT * FROM td_orders WHERE SHIPPING_ADDRESS IS NULL AND (CODE='Delivered' OR STATUS='Delivered')

--Ако в записа липсва данни за клиента Customer_id, то тогава този запис трябва да бъде прехвърлен към таблица td_suspisios_records
SELECT * FROM td_orders WHERE CUSTOMER_ID IS NULL OR CUSTOMER_NAME IS NULL --проверявам и по CUSTOMER_NAME, защото то също е част от данните за клиента

CREATE OR REPLACE TABLE td_suspisios_records
AS
SELECT $1 AS order_id, $2 AS customer_id, $3 AS customer_name,$4 AS order_date,  
$5 AS product, $6 AS quantity,$7 AS price,$8 AS discount,$9 AS total_amount, 
$10 AS payment_method, $11 AS shipping_address, $12 AS wrong_data, $13 AS Status
FROM @SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders/ecommerce_orders.csv
WHERE 1 = 2

SELECT * FROM td_suspisios_records;
------------------
INSERT INTO td_suspisios_records(ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, ORDER_DATE, PRODUCT, QUANTITY, PRICE,
DISCOUNT, TOTAL_AMOUNT, PAYMENT_METHOD, SHIPPING_ADDRESS, WRONG_DATA, STATUS)
SELECT * FROM td_orders WHERE CUSTOMER_ID IS NULL OR CUSTOMER_NAME IS NULL

--Ако липсва информация за платежния метод, коригирайте със стойност по подразбиране Unknown
SELECT * FROM td_orders WHERE PAYMENT_METHOD IS NULL --check

UPDATE td_orders SET PAYMENT_METHOD = 'Unknown' WHERE PAYMENT_METHOD IS NULL

--Някой от записите имат грешен формат, спрямо другите данни - ще откриете сами за какво говорим. Всеки запис с невалиден формат трябва да се прехвърли към таблица td_invalid_date_format , а финалните записи да се коригират, така че да бъдат в правилния формат.

SELECT * FROM td_orders WHERE TRY_TO_DATE(ORDER_DATE, 'YYYY-MM-DD')IS NULL  --check

CREATE TABLE td_invalid_date_format
AS
SELECT $1 AS order_id, $2 AS customer_id, $3 AS customer_name,$4 AS order_date,  
$5 AS product, $6 AS quantity,$7 AS price,$8 AS discount,$9 AS total_amount, 
$10 AS payment_method, $11 AS shipping_address, $12 AS wrong_data, $13 AS Status
FROM @SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders/ecommerce_orders.csv
WHERE 1 = 2

SELECT * FROM td_invalid_date_format;

INSERT INTO td_invalid_date_format
SELECT * FROM td_orders WHERE TRY_TO_DATE(ORDER_DATE, 'YYYY-MM-DD')IS NULL --TRY_TO_DATE проверява формата на датата

--Изтриите всички редове, които съдържат невалидни стойности за цена и количество поръчана стока. Тези стойности винаги трябва да бъдат положителни. Прехвърлете заподозрените записи в специфична таблица, с име по ваш избор.

SELECT * FROM td_orders WHERE QUANTITY<0 OR TOTAL_AMOUNT<0 --check

CREATE TABLE td_suspisios_quantity_amount
AS
SELECT $1 AS order_id, $2 AS customer_id, $3 AS customer_name,$4 AS order_date,  
$5 AS product, $6 AS quantity,$7 AS price,$8 AS discount,$9 AS total_amount, 
$10 AS payment_method, $11 AS shipping_address, $12 AS wrong_data, $13 AS Status
FROM @SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders/ecommerce_orders.csv
WHERE 1 = 2

SELECT * FROM td_suspisios_quantity_amount;
-----------------------
INSERT INTO td_suspisios_quantity_amount(ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, ORDER_DATE, PRODUCT, QUANTITY, PRICE,
DISCOUNT, TOTAL_AMOUNT, PAYMENT_METHOD, SHIPPING_ADDRESS, WRONG_DATA, STATUS)
SELECT * FROM td_orders WHERE QUANTITY<0 OR TOTAL_AMOUNT<0

DELETE FROM td_orders 
WHERE QUANTITY<0 OR TOTAL_AMOUNT<0

--Ако отстъпката е по малка от нула или по голяма от 50% то тя е невалидна, всички отстъпки над този диапазон, трябва да се трансформират във валидните си граници:
SELECT * FROM td_orders WHERE DISCOUNT<0.0 OR DISCOUNT>0.50 --checking
--за отрицателни стойности -- това е 0
UPDATE td_orders SET DISCOUNT = 0.0 WHERE DISCOUNT<0.0
--за стойности над 50% -- това е 50%
UPDATE td_orders SET DISCOUNT = 0.50 WHERE DISCOUNT>0.50

--Някой записи имат грешно калкулирана крайна цена, Цената се определя по формулата:
--количество стока * цена като се взима предвид и отстъпката

UPDATE td_orders
SET TOTAL_AMOUNT = QUANTITY * PRICE * (1 - DISCOUNT/100)

--Някой записи са маркирани като ДОСТАВЕНИ, но в тях не фигурира адрес за доставка. Всички такива записи трябва да променят своя статус на "Pending"

SELECT * FROM td_orders WHERE SHIPPING_ADDRESS IS NULL AND (CODE='Delivered' OR STATUS='Delivered')

UPDATE td_orders SET STATUS = 'Pending' WHERE SHIPPING_ADDRESS IS NULL AND (CODE='Delivered' OR STATUS='Delivered')

--Ако намерите повтарящи се записи, трябва да ги изтриете.
SELECT DISTINCT * FROM td_orders

DELETE FROM td_orders
WHERE (ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, ORDER_DATE, PRODUCT, QUANTITY, PRICE,
DISCOUNT, TOTAL_AMOUNT, PAYMENT_METHOD, SHIPPING_ADDRESS, CODE, STATUS)
IN (
  SELECT ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, ORDER_DATE, PRODUCT, QUANTITY, PRICE,
DISCOUNT, TOTAL_AMOUNT, PAYMENT_METHOD, SHIPPING_ADDRESS, CODE, STATUS
  FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY ORDER_ID, CUSTOMER_ID, CUSTOMER_NAME, ORDER_DATE, PRODUCT, QUANTITY, PRICE,
DISCOUNT, TOTAL_AMOUNT, PAYMENT_METHOD, SHIPPING_ADDRESS, CODE, STATUS ORDER BY ORDER_DATE) AS rn
    FROM td_orders
  )
  WHERE rn > 1
);

--Резултата от нашата работа е финална таблица td_clean_records съдържаща, корекции по описаните правила. 
CREATE TABLE td_clean_records
AS
SELECT $1 AS order_id, $2 AS customer_id, $3 AS customer_name,$4 AS order_date,  
$5 AS product, $6 AS quantity,$7 AS price,$8 AS discount,$9 AS total_amount, 
$10 AS payment_method, $11 AS shipping_address, $12 AS data, $13 AS Status
FROM @SPARROW_ECOMERSE_DB.orders_management.ecomerse_orders/ecommerce_orders.csv
WHERE 1 = 2

SELECT * FROM td_clean_records;

INSERT INTO td_clean_records
SELECT * FROM td_orders
WHERE ORDER_ID NOT IN(
SELECT ORDER_ID FROM td_for_review
UNION
SELECT ORDER_ID FROM td_suspisios_records
UNION
SELECT ORDER_ID FROM td_invalid_date_format
UNION
SELECT ORDER_ID FROM td_suspisios_quantity_amount
);