 -- First filter agreements excluding regular Co-op
DROP TABLE IF EXISTS filtered_agreements;
CREATE TEMP TABLE filtered_agreements AS (
    SELECT
        a.region_id,
        a.marketplace_id,
        CAST(a.product_group_id AS INT) AS product_group_id,
        a.agreement_id,
        a.agreement_title,
        a.agreement_start_date,
        a.agreement_end_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name
    FROM andes.rs_coop_ddl.coop_agreements a
    WHERE a.region_id=1
        AND a.marketplace_id = 7
        AND a.product_group_id IN  (510, 364, 325, 199, 194, 121, 75)  
        AND a.signed_flag=1
        AND a.agreement_start_date >= TO_DATE('2025-06-01', 'YYYY-MM-DD')                                   -- adjust as needed   
        -- AND (a.agreement_end_date IS NULL OR a.agreement_end_date >= TO_DATE('2025-06-01', 'YYYY-MM-DD'))   -- adjust as needed 
        AND a.agreement_id IS NOT NULL
        AND UPPER(a.activity_type_name) != 'CO-OP ACTIVITIES'
);


DROP TABLE IF EXISTS agreement_coop;
CREATE TEMP TABLE agreement_coop AS (
    SELECT 
        a.agreement_id,
        r.vendor_code,
        a.agreement_title,
        a.agreement_start_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name,
        TO_CHAR(TO_DATE(r.receive_day, 'YYYY-MM-DD'), 'YYYY-MM') as coop_receive_yr_mo,
        r.coop_amount_currency,
        SUM(r.coop_amount) as coop_amount
    FROM filtered_agreements a
        INNER JOIN andes.rs_coop_ddl.coop_dsi_calculation_results r
        ON a.agreement_id = r.agreement_id
    WHERE r.region_id=1
        AND r.asin_marketplace_id = 7
        AND r.gl_product_group_id IN  (510, 364, 325, 199, 194, 121, 75)            
        AND TO_DATE(r.receive_day,'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-06-01','YYYY-MM-DD')          -- adjust as needed     
            AND TO_DATE('2025-10-03', 'YYYY-MM-DD')             -- adjust as needed    
    GROUP BY
        a.agreement_id,
        -- a.signed_flag,
        r.vendor_code,
        a.agreement_title,
        a.agreement_start_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name,
        TO_CHAR(TO_DATE(r.receive_day, 'YYYY-MM-DD'), 'YYYY-MM'),
        r.coop_amount_currency
);

DROP TABLE IF EXISTS vendor_agreements;
CREATE TEMP TABLE vendor_agreements AS (
    SELECT
        a.coop_receive_yr_mo,
        CAST(a.agreement_start_date AS DATE) AS agreement_start_date,
        a.agreement_id, 
        CAST(v.primary_vendor_code AS varchar) AS primary_vendor_code,
        v.vendor_name,
        a.funding_type_name,
        a.activity_type_name,
        a.agreement_title,
        a.owned_by_user_id,
        a.coop_amount,
        a.coop_amount_currency
    FROM agreement_coop a
        LEFT JOIN  andes.vendorcode_management.o_vendors v
        ON a.vendor_code = v.vendor_code
    WHERE coop_amount <> 0
        AND UPPER(funding_type_name) != 'ACCRUAL'
);

select * from vendor_agreements;
