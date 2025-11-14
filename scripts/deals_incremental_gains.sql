
/******************************************************************
 *              Initial Agreement Filtering
 ******************************************************************/
-- base agreement filtering
DROP TABLE IF EXISTS filtered_agreements;
CREATE TEMP TABLE filtered_agreements AS (
    SELECT
        a.region_id,
        a.marketplace_id,
        CAST(a.product_group_id AS INT) AS product_group_id,
        a.agreement_id,
        a.agreement_start_date,
        a.agreement_end_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name
    FROM andes.rs_coop_ddl.coop_agreements a
    WHERE a.region_id=1
        AND a.marketplace_id = 7
        AND a.product_group_id IN (510, 364, 325, 199, 194, 121, 75)  
        AND a.signed_flag=1
        AND a.agreement_start_date >= TO_DATE('2025-01-01', 'YYYY-MM-DD')
        -- AND a.agreement_start_date <= TO_DATE('2025-10-31', 'YYYY-MM-DD')
        AND (a.agreement_end_date IS NULL OR a.agreement_end_date >= TO_DATE('2025-01-01', 'YYYY-MM-DD'))
        AND a.agreement_id IS NOT NULL
        AND UPPER(a.funding_type_name) = UPPER('FLEXIBLE AGREEMENT')
        AND CAST(a.signed_flag as int)=1
        -- AND a.owned_by_user_id = 'taruncho' -- test
);


/******************************************************************
 *          ASIN Based Flex Agreements Processing
 ******************************************************************/
DROP TABLE IF EXISTS asin_based_flex_agreements;
CREATE TEMP TABLE asin_based_flex_agreements AS (
    SELECT 
        a.region_id,
        a.marketplace_id,
        CAST(a.product_group_id AS INT) AS product_group_id,
        a.agreement_id,
        a.agreement_start_date,
        a.agreement_end_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name
        -- a.promotion_type
    FROM filtered_agreements a
    WHERE UPPER(a.activity_type_name) IN (
        UPPER('Promotions - Price Discounts'), 
        UPPER('Promotions - Special Marketing Events'),
        UPPER('Product Cost - Margin Improvement')
    )
        -- AND a.agreement_id = 92035245 -- test
);


DROP TABLE IF EXISTS asin_based_flex_agreements_asins;
CREATE TEMP TABLE asin_based_flex_agreements_asins AS (
    SELECT 
        r.asin,
        r.customer_shipment_item_id,
        'N/A (ASIN based flex)' as promotion_key,
        'N/A (ASIN based flex)' as paws_promotion_id,
        'ASIN based flex' as purpose,
        p.agreement_start_date as start_datetime,
        p.agreement_end_date as end_datetime,
        r.region_id,
        r.marketplace_id as marketplace_key,
        p.product_group_id,
        p.owned_by_user_id,
        p.funding_type_name,
        p.activity_type_name,
        p.agreement_id,
        'ASIN based flex' as flex_type,
        SUM(r.quantity) as quantity,
        SUM(r.coop_amount) as coop_amount
    FROM asin_based_flex_agreements p
        LEFT JOIN andes.rs_coop_ddl.COOP_CSI_CALCULATION_RESULTS  r 
        ON p.agreement_id = r.agreement_id 
    WHERE r.region_id = 1
        AND r.marketplace_id = 7
        AND r.gl_product_group_id IN (510, 364, 325, 199, 194, 121, 75)  
        AND TO_DATE(r.order_datetime, 'YYYY-MM-DD') 
            BETWEEN p.agreement_start_date 
            AND COALESCE(p.agreement_end_date, TO_DATE('2025-11-30', 'YYYY-MM-DD'))
        -- AND r.asin='B0DF8WNZXZ'   -- test
    GROUP BY 
        r.asin,
        r.customer_shipment_item_id, 
        p.agreement_start_date,
        p.agreement_end_date,
        r.region_id,
        r.marketplace_id,
        p.product_group_id,
        p.owned_by_user_id,
        p.funding_type_name,
        p.activity_type_name,
        p.agreement_id
);

 
-- First create an intermediary filtered shipments table
DROP TABLE IF EXISTS filtered_shipments;
CREATE TEMP TABLE filtered_shipments AS (
    SELECT 
        customer_shipment_item_id,
        our_price
    FROM andes.booker.D_UNIFIED_CUST_SHIPMENT_ITEMS
    WHERE region_id = 1
        AND marketplace_id = 7
        AND gl_product_group IN (510, 364, 325, 199, 194, 121, 75)
        AND TO_DATE(order_datetime, 'YYYY-MM-DD') >= TO_DATE('2025-01-01', 'YYYY-MM-DD')
        AND TO_DATE(order_datetime, 'YYYY-MM-DD') <= TO_DATE('2025-12-31', 'YYYY-MM-DD')
);


-- Then create the final table with the join
DROP TABLE IF EXISTS asin_based_coop_result;
CREATE TEMP TABLE asin_based_coop_result AS (
    SELECT
        a.asin,
        a.promotion_key,
        a.paws_promotion_id,
        a.purpose,
        a.start_datetime,
        a.end_datetime,
        a.region_id,
        a.marketplace_key,
        a.product_group_id,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name,
        o.our_price as promotion_pricing_amount,
        a.agreement_id,
        a.flex_type,
        SUM(a.quantity) AS quantity,
        SUM(a.coop_amount) AS coop_amount
    FROM asin_based_flex_agreements_asins a
        LEFT JOIN filtered_shipments o
        ON a.customer_shipment_item_id = o.customer_shipment_item_id
    WHERE o.our_price > 0
    GROUP BY
        a.asin,
        a.promotion_key,
        a.paws_promotion_id,
        a.purpose,
        a.start_datetime,
        a.end_datetime,
        a.region_id,
        a.marketplace_key,
        a.product_group_id,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name,
        o.our_price,
        a.agreement_id,
        a.flex_type
);


/******************************************************************
 *              Promotional Flex Agreements Processing
 ******************************************************************/
-- Get promotional flex agreements
DROP TABLE IF EXISTS promotional_flex_agreements;
CREATE TEMP TABLE promotional_flex_agreements AS (
    SELECT
        fa.agreement_id,
        p.promotion_key,
        p.paws_promotion_id,
        p.deal_id,
        p.purpose,
        p.start_datetime,
        p.end_datetime,
        p.region_id,
        p.marketplace_key,
        fa.product_group_id,
        fa.owned_by_user_id,
        fa.funding_type_name,
        fa.activity_type_name,
        p.promotion_type
    FROM filtered_agreements fa
        LEFT JOIN andes.pdm.dim_promotion p
        ON fa.agreement_id = p.coop_agreement_id
    WHERE 
        p.start_datetime >= TO_DATE('2025-01-01', 'YYYY-MM-DD')
        AND p.end_datetime <= TO_DATE('2025-12-31', 'YYYY-MM-DD')
        AND p.promotion_type != 'Coupon'
        -- AND p.paws_promotion_id = '311800571013' -- test
    --     p.start_datetime <= TO_DATE('2025-10-31', 'YYYY-MM-DD')
    --     AND p.end_datetime >= TO_DATE('2025-01-01', 'YYYY-MM-DD')
);


DROP TABLE IF EXISTS temp_flex_promo_asin;
CREATE TEMP TABLE temp_flex_promo_asin AS (
    SELECT
        pa.asin,
        p.promotion_key,
        p.paws_promotion_id,
        p.purpose,
        p.start_datetime,
        p.end_datetime,
        p.region_id,
        p.marketplace_key,
        p.product_group_id,
        p.owned_by_user_id,
        p.funding_type_name,
        p.activity_type_name,
        pa.promotion_pricing_amount,
        p.agreement_id,
        'Flex Promo' as flex_type
    FROM promotional_flex_agreements p
        LEFT JOIN andes.pdm.dim_promotion_asin pa
        ON pa.promotion_key = p.promotion_key
        -- AND pa.region_id = p.region_id
        -- and pa.asin = 'B07JQM8BR1' -- test
    WHERE pa.asin_approval_status = 'Approved'
);
  

-- Create daily aggregated coop results
DROP TABLE IF EXISTS flex_coop_results;
CREATE TEMP TABLE flex_coop_results AS (
    SELECT 
        r.asin,
        t.promotion_key,
        t.paws_promotion_id,
        t.purpose,
        t.start_datetime,
        t.end_datetime,
        r.region_id,
        r.marketplace_id as marketplace_key,
        r.gl_product_group_id as product_group_id,
        t.owned_by_user_id,
        t.funding_type_name,
        t.activity_type_name,
        t.promotion_pricing_amount,
        r.agreement_id,
        'Flex Promo' as flex_type,
        SUM(r.quantity) as quantity,
        SUM(r.coop_amount) as coop_amount
    FROM andes.rs_coop_ddl.coop_csi_calculation_results r
        INNER JOIN temp_flex_promo_asin t
        ON t.asin = r.asin
        -- AND t.region_id = r.region_id
        AND t.agreement_id = r.agreement_id
    WHERE r.region_id=1
        AND r.marketplace_id = 7
        AND r.gl_product_group_id IN (510, 364, 325, 199, 194, 121, 75)
        AND r.agreement_id IS NOT NULL
        AND TO_DATE(r.order_datetime,'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-01-01','YYYY-MM-DD')
            AND TO_DATE('2025-11-30', 'YYYY-MM-DD')
        AND r.is_valid = 'Y'
        AND r.vendor_code IS NOT NULL
        -- AND t.paws_promotion_id=311800571013    -- test
    GROUP BY 
        r.asin,
        t.promotion_key,
        t.paws_promotion_id,
        t.purpose,
        t.start_datetime,
        t.end_datetime,
        r.region_id,
        r.marketplace_id,
        r.gl_product_group_id,
        t.owned_by_user_id,
        t.funding_type_name,
        t.activity_type_name,
        t.promotion_pricing_amount,
        r.agreement_id
);


/******************************************************************
 *                          Combine 
 ******************************************************************/
 DROP TABLE IF EXISTS combined_flex_agreements;
CREATE TEMP TABLE combined_flex_agreements AS ( 
    select
        asin,
        NULLIF(promotion_key, 'N/A - ASIN BASED PROMO')::varchar as promotion_key,
        NULLIF(paws_promotion_id, 'N/A - ASIN BASED PROMO')::varchar as paws_promotion_id,
        purpose,
        start_datetime,
        end_datetime,
        region_id,
        marketplace_key,
        product_group_id,
        owned_by_user_id,
        funding_type_name,
        activity_type_name,
        promotion_pricing_amount,
        agreement_id,
        flex_type,
        quantity,
        coop_amount
    FROM asin_based_coop_result
    UNION ALL
    SELECT
        asin,
        CAST(promotion_key as varchar) as promotion_key,
        CAST(paws_promotion_id as varchar) as paws_promotion_id,
        purpose,
        start_datetime,
        end_datetime,
        region_id,
        marketplace_key,
        product_group_id,
        owned_by_user_id,
        funding_type_name,
        activity_type_name,
        promotion_pricing_amount,
        agreement_id,
        flex_type,
        quantity,
        coop_amount
    FROM flex_coop_results
);
    
    
/******************************************************************
 *                      T4W Calculations
 ******************************************************************/
-- Date ranges for T4W
DROP TABLE IF EXISTS deal_date_ranges;
CREATE TEMP TABLE deal_date_ranges AS (
    SELECT distinct
        asin, 
        CAST(paws_promotion_id AS varchar) as paws_promotion_id,
        agreement_id,
        start_datetime as min_date,
        end_datetime as max_date,
        flex_type
    from combined_flex_agreements
);


-- Filtered shipments for T4W
DROP TABLE IF EXISTS filtered_shipments;
CREATE TEMP TABLE filtered_shipments AS (
    SELECT DISTINCT 
        o.gl_product_group,
        o.asin,
        dr.agreement_id,
        dr.paws_promotion_id,
        dr.flex_type,
        o.customer_shipment_item_id,
        o.order_datetime,
        o.shipped_units,
        CASE 
            WHEN dr.flex_type = 'ASIN' THEN 
                DATE_TRUNC('week', dr.min_date) - interval '28 days'
            ELSE 
                DATE_TRUNC('week', TO_DATE(dr.min_date, 'YYYY-MM-DD')) - interval '28 days'
        END as t4w_start_date,
        CASE 
            WHEN dr.flex_type = 'ASIN' THEN 
                DATE_TRUNC('week', dr.min_date) - interval '1 day'
            ELSE 
                DATE_TRUNC('week', TO_DATE(dr.min_date, 'YYYY-MM-DD')) - interval '1 day'
        END as t4w_end_date
    FROM "andes"."booker"."d_unified_cust_shipment_items" o
        INNER JOIN deal_date_ranges dr 
        ON o.asin = dr.asin
    WHERE o.region_id = 1
        AND o.marketplace_id = 7
        AND o.gl_product_group IN (510, 364, 325, 199, 194, 121, 75)
        AND o.shipped_units > 0
        AND o.is_retail_merchant = 'Y'
        AND o.order_condition != 6
);

-- T4W ASP Calculation
DROP TABLE IF EXISTS t4w;
CREATE TEMP TABLE t4w AS (
    SELECT
        o.asin,
        o.paws_promotion_id,
        o.agreement_id,
        o.flex_type,
        COALESCE(
            SUM(CASE WHEN cp.revenue_share_amt IS NOT NULL THEN cp.revenue_share_amt ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN o.shipped_units IS NOT NULL THEN o.shipped_units ELSE 0 END), 0),
        0) AS t4w_asp
    FROM filtered_shipments o
        LEFT JOIN andes.contribution_ddl.o_wbr_cp_na cp
        ON o.customer_shipment_item_id = cp.customer_shipment_item_id 
        AND o.asin = cp.asin
    WHERE TO_DATE(o.order_datetime, 'YYYY-MM-DD')
        BETWEEN o.t4w_start_date AND o.t4w_end_date
        AND cp.manufacturer_code IS NOT NULL
    GROUP BY 
        o.asin,
        o.paws_promotion_id,
        o.agreement_id,
        o.flex_type
);


/******************************************************************
 *                  Final Output Generation
 ******************************************************************/
DROP TABLE IF EXISTS agreement_calcs_output;
CREATE TEMP TABLE agreement_calcs_output AS (
    SELECT
        c.region_id,
        c.marketplace_key,
        c.asin,
        c.promotion_key,
        CAST(c.paws_promotion_id AS VARCHAR) as paws_promotion_id,
        c.purpose,
        c.agreement_id,
        c.start_datetime,
        c.end_datetime,
        c.product_group_id,
        c.owned_by_user_id,
        c.funding_type_name,
        c.activity_type_name,
        c.promotion_pricing_amount,
        c.coop_amount as coop_amount,
        tw.t4w_asp,
        CAST(mam.owning_vendor_code AS VARCHAR) as vendor_code,
        CAST(mam.owning_vendor_name AS VARCHAR) as vendor_name,
        c.quantity as shipped_units,
        c.flex_type
    FROM combined_flex_agreements c
        LEFT JOIN t4w tw
            ON c.asin = tw.asin
            AND c.flex_type = tw.flex_type
            AND tw.paws_promotion_id = c.paws_promotion_id
            AND tw.agreement_id = c.agreement_id
        LEFT JOIN andes.BOOKER.D_MP_ASIN_MANUFACTURER mam  
            ON mam.asin = c.asin
    WHERE c.coop_amount IS NOT NULL
        AND mam.owning_vendor_code IS NOT NULL
        AND mam.region_id=1
        AND mam.marketplace_id=7
);

-- don't use vendor name col here
DROP TABLE IF EXISTS calcs_vendor;
CREATE TEMP TABLE calcs_vendor AS (
    SELECT
        a.region_id,
        a.marketplace_key,
        a.product_group_id,
        a.asin,
        a.owned_by_user_id,
        c.company_code,
        a.vendor_code,
        a.vendor_name,
        a.promotion_key,
        a.paws_promotion_id,
        a.flex_type,
        a.purpose,
        a.agreement_id,
        a.start_datetime,
        a.end_datetime,
        a.funding_type_name,
        a.activity_type_name,
        a.promotion_pricing_amount,
        a.coop_amount,
        a.t4w_asp,
        SUM(a.shipped_units) as shipped_units
    FROM agreement_calcs_output a
        LEFT JOIN andes.roi_ml_ddl.vendor_company_codes c
        ON a.vendor_code = c.vendor_code
    GROUP BY         
        a.region_id,
        a.marketplace_key,
        a.product_group_id,
        a.asin,
        a.owned_by_user_id,
        c.company_code,
        a.vendor_code,
        a.vendor_name,
        a.promotion_key,
        a.paws_promotion_id,
        a.flex_type,
        a.purpose,
        a.agreement_id,
        a.start_datetime,
        a.end_datetime,
        a.funding_type_name,
        a.activity_type_name,
        a.promotion_pricing_amount,
        a.coop_amount,
        a.t4w_asp
);

-- Display results
select * from calcs_vendor;