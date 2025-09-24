/* 
 Connect agreements, ASINs, and coop 
*/
-- First filter agreements excluding regular Co-op
DROP TABLE IF EXISTS filtered_agreements;
CREATE TEMP TABLE filtered_agreements AS (
    SELECT
        a.region_id,
        a.marketplace_id,
        CAST(a.product_group_id AS integer) AS product_group_id,
        a.agreement_id,
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
        AND a.agreement_start_date <= TO_DATE('2025-07-31', 'YYYY-MM-DD')
        AND (a.agreement_end_date IS NULL OR a.agreement_end_date >= TO_DATE('2025-07-01', 'YYYY-MM-DD'))
        AND a.agreement_id IS NOT NULL
        AND UPPER(a.activity_type_name) != 'CO-OP ACTIVITIES'
);

DROP TABLE IF EXISTS promo_agreements;
CREATE TEMP TABLE promo_agreements AS (
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
        fa.activity_type_name
    FROM filtered_agreements fa
        LEFT JOIN andes.pdm.dim_promotion p
        ON fa.agreement_id = p.coop_agreement_id
        AND fa.region_id = p.region_id
        AND fa.marketplace_id = p.marketplace_key
    WHERE p.region_id = 1
        AND p.marketplace_key = 7
        AND p.start_datetime <= TO_DATE('2025-07-31', 'YYYY-MM-DD')
        AND p.end_datetime >= TO_DATE('2025-07-01', 'YYYY-MM-DD')
);


-- Then proceed with your existing temp_promo_asin creation
DROP TABLE IF EXISTS temp_promo_asin;
CREATE TEMP TABLE temp_promo_asin AS (
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
        p.agreement_id
    FROM promo_agreements p
        LEFT JOIN andes.pdm.dim_promotion_asin pa
        ON pa.promotion_key = p.promotion_key
        AND pa.region_id = p.region_id
        AND pa.marketplace_key = p.marketplace_key
        AND pa.product_group_key = p.product_group_id
);


-- First create daily aggregated coop results
DROP TABLE IF EXISTS daily_coop_results;
CREATE TEMP TABLE daily_coop_results AS (
    SELECT 
        r.asin,
        r.region_id,
        r.asin_marketplace_id,
        r.gl_product_group_id,
        r.agreement_id,
        TO_DATE(r.order_datetime,'YYYY-MM-DD') as order_date,
        SUM(r.quantity) as daily_quantity,
        SUM(r.coop_amount) as daily_coop_amount
    FROM andes.rs_coop_ddl.coop_csi_calculation_results r
        INNER JOIN temp_promo_asin t
        ON t.asin = r.asin
        AND t.region_id = r.region_id
        AND t.marketplace_key = r.asin_marketplace_id
        and t.product_group_id = r.gl_product_group_id
        AND t.agreement_id = r.agreement_id
    WHERE r.region_id=1
        AND r.asin_marketplace_id = 7
        AND r.gl_product_group_id IN  (510, 364, 325, 199, 194, 121, 75)
        AND r.agreement_id IS NOT NULL
        AND TO_DATE(r.order_datetime,'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-07-01','YYYY-MM-DD') 
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD')
        AND r.is_valid = 'Y'
    GROUP BY 
        r.asin,
        r.region_id,
        r.asin_marketplace_id,
        r.gl_product_group_id,
        r.agreement_id,
        TO_DATE(r.order_datetime,'YYYY-MM-DD')
);

-- Finally join with the aggregated coop results
DROP TABLE IF EXISTS agreement_calcs;
CREATE TEMP TABLE agreement_calcs AS (
    SELECT
        t.asin,
        t.promotion_key,
        t.paws_promotion_id,
        t.purpose,
        t.start_datetime,
        t.end_datetime,
        t.region_id,
        t.marketplace_key,
        t.product_group_id,
        t.owned_by_user_id,
        t.funding_type_name,
        t.activity_type_name,
        t.promotion_pricing_amount,
        r.daily_coop_amount as coop_amount,
        SUM(r.daily_quantity) as quantity_sum
    FROM temp_promo_asin t
        LEFT JOIN daily_coop_results r
        ON t.asin = r.asin
        AND t.region_id = r.region_id
        AND t.marketplace_key = r.asin_marketplace_id
        AND t.product_group_id = r.gl_product_group_id
        AND t.agreement_id = r.agreement_id
    WHERE r.daily_coop_amount IS NOT NULL
    GROUP BY 
        t.asin,
        t.promotion_key,
        t.paws_promotion_id,
        t.purpose,
        t.start_datetime,
        t.end_datetime,
        t.region_id,
        t.marketplace_key,
        t.product_group_id,
        t.owned_by_user_id,
        t.funding_type_name,
        t.activity_type_name,
        t.promotion_pricing_amount,
        r.daily_coop_amount
);

DROP TABLE IF EXISTS deal_asins;
CREATE TEMP TABLE deal_asins AS  (
    SELECT DISTINCT
        asin,
        paws_promotion_id,
        start_datetime,
        end_datetime
    FROM agreement_calcs
);


/* 
 T4W ASP Calculation 
  */
-- unique promo start & end dates for each deal asin
DROP TABLE IF EXISTS deal_date_ranges;
CREATE TEMP TABLE deal_date_ranges AS  (
    SELECT DISTINCT 
        asin,
        paws_promotion_id,
        MIN(start_datetime) as min_date,
        MAX(end_datetime) as max_date 
    FROM deal_asins
    GROUP BY 
        asin,
        paws_promotion_id
);

-- filter for shipped units from
 T4W pre event to event end date
DROP TABLE IF EXISTS filtered_shipments;
CREATE TEMP TABLE filtered_shipments AS  (
    SELECT DISTINCT 
        o.gl_product_group,
        o.asin,
        o.customer_shipment_item_id,
        o.order_datetime,
        o.shipped_units
    FROM "andes"."booker"."d_unified_cust_shipment_items" o
    JOIN deal_date_ranges dr ON o.asin = dr.asin
    WHERE o.region_id = 1                                    -- NA
        AND o.marketplace_id = 7                             -- CA
        AND TO_DATE(o.order_datetime, 'YYYY-MM-DD') 
            BETWEEN DATE_TRUNC('week', TO_DATE(dr.min_date, 'YYYY-MM-DD')) - interval '28 days'
            AND TO_DATE(dr.max_date, 'YYYY-MM-DD')
        AND o.gl_product_group 
            IN (510, 364, 325, 199, 194, 121, 75)            -- CONSUMABLES
        AND o.shipped_units > 0
        AND o.is_retail_merchant = 'Y'
        AND o.order_condition != 6                           -- not cancelled/returned
);


--  T4W revenue, shipped units, & ASP
DROP TABLE IF EXISTS t4w;
CREATE TEMP TABLE t4w AS (
    SELECT
        o.asin,
        dr.paws_promotion_id,
        COALESCE(
            SUM(CASE WHEN cp.revenue_share_amt IS NOT NULL THEN cp.revenue_share_amt ELSE 0 END) / 
            NULLIF(SUM(CASE WHEN o.shipped_units IS NOT NULL THEN o.shipped_units ELSE 0 END), 0),
        0) AS t4w_asp
    FROM filtered_shipments o
        LEFT JOIN deal_date_ranges dr 
            ON o.asin = dr.asin
        LEFT JOIN andes.contribution_ddl.o_wbr_cp_na cp
            ON o.customer_shipment_item_id = cp.customer_shipment_item_id 
            AND o.asin = cp.asin
    WHERE TO_DATE(o.order_datetime, 'YYYY-MM-DD')
        BETWEEN DATE_TRUNC('week', TO_DATE(dr.min_date, 'YYYY-MM-DD')) - interval '28 days'
        AND DATE_TRUNC('week', TO_DATE(dr.min_date, 'YYYY-MM-DD')) - interval '1 day'
    GROUP BY 
        o.asin,
        dr.paws_promotion_id
);


DROP TABLE IF EXISTS agreement_calcs_output;
CREATE TEMP TABLE agreement_calcs_output AS (
    SELECT
        t.region_id,
        t.marketplace_key,
        t.asin,
        t.promotion_key,
        CAST(t.paws_promotion_id AS VARCHAR),
        t.purpose,
        r.agreement_id,
        t.start_datetime,
        t.end_datetime,
        t.product_group_id,
        t.owned_by_user_id,
        t.funding_type_name,
        t.activity_type_name,
        t.promotion_pricing_amount,
        r.daily_coop_amount as coop_amount,
        tw.t4w_asp,
        CAST(mam.owning_vendor_code AS VARCHAR) as vendor_code,
        CAST(mam.owning_vendor_name AS VARCHAR) as vendor_name,
        SUM(r.daily_quantity) as shipped_units
    FROM temp_promo_asin t
        LEFT JOIN daily_coop_results r
            ON t.asin = r.asin
            AND t.region_id = r.region_id
            AND t.marketplace_key = r.asin_marketplace_id
            AND t.product_group_id = r.gl_product_group_id
            AND t.agreement_id = r.agreement_id
        LEFT JOIN t4w tw
            ON t.asin = tw.asin
            AND tw.paws_promotion_id = t.paws_promotion_id
        LEFT JOIN andes.BOOKER.D_MP_ASIN_MANUFACTURER mam 
            ON mam.region_id = t.region_id
            AND mam.marketplace_id = t.marketplace_key
            AND mam.asin = t.asin
    WHERE r.daily_coop_amount IS NOT NULL
    GROUP BY 
        t.asin,
        t.promotion_key,
        t.paws_promotion_id,
        t.purpose,
        r.agreement_id,
        t.start_datetime,
        t.end_datetime,
        t.region_id,
        t.marketplace_key,
        t.product_group_id,
        t.owned_by_user_id,
        t.funding_type_name,
        t.activity_type_name,
        t.promotion_pricing_amount,
        r.daily_coop_amount,
        tw.t4w_asp,
        mam.owning_vendor_code,
        mam.owning_vendor_name
);

select * from agreement_calcs_output;