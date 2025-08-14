DROP TABLE IF EXISTS filtered_agreements;
CREATE TEMP TABLE filtered_agreements AS (
    SELECT 
        a.agreement_id,
        a.signed_flag,
        a.vendor_id,
        a.agreement_title,
        TO_CHAR(TO_DATE(a.agreement_start_date, 'YYYY-MM-DD'), 'YYYY-MM') as agreement_start_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name
    FROM andes.rs_coop_ddl.COOP_AGREEMENTS a
    WHERE a.region_id=1
        AND a.marketplace_id = 7                                                    -- CA
        AND a.product_group_id IN (510, 364, 325, 199, 194, 121, 75)                -- consumables
);

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
        SUM(
            case 
                when r.coop_amount_currency = 'CAD' 
                then (coop_amount/1.43) 
                else coop_amount 
            end
        ) as coop_amount_usd                                                        
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
        TO_CHAR(TO_DATE(r.receive_day, 'YYYY-MM-DD'), 'YYYY-MM')
);

DROP TABLE IF EXISTS vendor_agreements;
CREATE TEMP TABLE vendor_agreements AS (
    SELECT
        a.agreement_id, 
        v.primary_vendor_code,
        v.vendor_name,
        a.agreement_title,
        a.agreement_start_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name,
        a.coop_receive_yr_mo,
        a.coop_amount_usd
    FROM agreement_coop a
        LEFT JOIN  andes.vendorcode_management.o_vendors v
        ON a.vendor_id = v.vendor_id
    WHERE coop_amount_usd <> 0
);

select * from vendor_agreements;
