 

DROP TABLE IF EXISTS agreement_coop;
CREATE TEMP TABLE agreement_coop AS (
    SELECT 
        a.agreement_id,
        a.signed_flag,
        a.vendor_id,
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
            BETWEEN TO_DATE('2025-07-01','YYYY-MM-DD') 
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD')                                 
    GROUP BY
        a.agreement_id,
        a.signed_flag,
        a.vendor_id,
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
        a.agreement_start_date,
        a.agreement_id, 
        maa.gl_product_group,
        v.primary_vendor_code,
        v.vendor_name,
        a.funding_type_name,
        a.activity_type_name,
        a.agreement_title,
        a.owned_by_user_id,
        a.coop_amount,
        a.coop_amount_currency
    FROM agreement_coop a
        LEFT JOIN  andes.vendorcode_management.o_vendors v
            ON a.vendor_id = v.vendor_id
        INNER JOIN andes.booker.d_mp_asin_attributes maa
            ON maa.asin = a.asin
            AND maa.marketplace_id = 7
            AND maa.region_id =1
            AND maa.gl_product_group IN (510, 364, 325, 199, 194, 121, 75)
    WHERE coop_amount <> 0
        AND UPPER(funding_type_name) != 'ACCRUAL'
);

select * from vendor_agreements;
