-- connect deals with specific asins
DROP TABLE IF EXISTS filtered_promos;
CREATE TEMP TABLE filtered_promos AS (
    SELECT 
        p.PAWS_PROMOTION_ID,
        p.start_datetime,
        p.end_datetime,
        p.promotion_key,
        p.region_id,
        p.marketplace_key
    FROM "andes"."pdm"."dim_promotion" p
    WHERE p.region_id = 1
        AND p.marketplace_key = 7
        AND p.paws_promotion_id::VARCHAR IN (
        -- Add your promo ids
        '311891281213','312189353513','312284734313','312284966513','312296506113','312303557813','312303558213','312303558313','312307739313','312315682113',
        '312356861213','312403287313','312468804813','312471003013','312480501713','312480501813','312480505813','312480716813','312480938913','312481380413',
        '312538212813','312874627313','312875066813','312875945913','312943782513','313110732213','313111172413','313111172713','313111612713','313143633313',
        '313171119213','313171339613','313177243613','313180501713','313180502413','313182701613','313233066313'
    )      
);


-- get promo pricing & vendor funding
DROP TABLE IF EXISTS deal_asins;
CREATE TEMP TABLE deal_asins AS (
    SELECT
        p.*,
        pa.asin,
        pa.asin_approval_status,
        pa.promotion_pricing_amount,
        pa.total_vendor_funding
    FROM filtered_promos p
        JOIN "andes"."pdm"."dim_promotion_asin" pa
            ON pa.promotion_key = p.promotion_key
            AND pa.region_id = p.region_id
            AND p.marketplace_key = pa.marketplace_key
    -- WHERE pa.asin_approval_status = 'APPROVED'
);

-- get shipped units
DROP TABLE IF EXISTS filtered_shipments;
CREATE TEMP TABLE filtered_shipments AS (

    WITH deal_date_ranges AS (
        SELECT DISTINCT 
            MIN(TO_DATE(start_datetime,'YYYY-MM-DD')) as min_date,
            MAX(TO_DATE(end_datetime,'YYYY-MM-DD')) as max_date 
        FROM deal_asins
    )

    SELECT 
        o.asin,
        o.customer_shipment_item_id,
        o.order_datetime,
        o.shipped_units
    FROM "andes"."booker"."d_unified_cust_shipment_items" o,
        deal_date_ranges
    WHERE TO_DATE(o.order_datetime, 'YYYY-MM-DD') >= min_date
        AND TO_DATE(o.order_datetime, 'YYYY-MM-DD') <= max_date
        AND o.region_id = 1
        AND o.marketplace_id = 7 
        AND o.gl_product_group IN (510, 364, 325, 199, 194, 121, 75)
);


-- and calculate pre-deal (T4W) ASP, based on promo start date 
DROP TABLE IF EXISTS t4w_promo_asp;
CREATE TEMP TABLE t4w_promo_asp AS (
    SELECT 
        d.asin,
        SUM(o.shipped_units) as shipped_units,
        AVG(cp.revenue_share_amt / o.shipped_units) as asp
    FROM filtered_shipments o
        RIGHT JOIN deal_asins d
            ON o.asin = d.asin
            -- AND o.marketplace_id=d.marketplace_key
            -- AND o.region_id=d.region_id
            -- and o.gl_product_group = d.gl_product_group
        INNER JOIN andes.contribution_ddl.o_wbr_cp_na cp
            ON o.customer_shipment_item_id = cp.customer_shipment_item_id 
            AND o.asin = cp.asin
            AND o.marketplace_id = cp.marketplace_id
            AND o.region_id = cp.region_id
     -- filter for t4w prior to promo start date
    WHERE o.order_datetime 
        BETWEEN TO_DATE('2025-07-08', 'YYYY-MM-DD')     -- promo start day
                - interval '29 days'
        AND TO_DATE('2025-07-08', 'YYYY-MM-DD')         -- promo start day
                - interval '1 days'
    GROUP BY d.asin
);


-- final output
DROP TABLE IF EXISTS deals_asin_details;
CREATE TEMP TABLE deals_asin_details AS (
    SELECT 
        da.PAWS_PROMOTION_ID,
        da.start_datetime,
        da.end_datetime,
        da.promotion_key,
        da.region_id,
        da.marketplace_key,
        da.asin,
        asp.asp,
        da.asin_approval_status,
        da.promotion_pricing_amount,
        da.total_vendor_funding,
        SUM(o.shipped_units) as shipped_units
    FROM deal_asins da
        LEFT JOIN filtered_shipments o
            ON o.asin = da.asin
            AND o.order_datetime >= da.start_datetime
            AND o.order_datetime <= da.end_datetime
        INNER JOIN t4w_promo_asp asp
            ON asp.asin = da.asin
    GROUP BY 
        da.PAWS_PROMOTION_ID,
        da.start_datetime,
        da.end_datetime,
        da.promotion_key,
        da.region_id,
        da.marketplace_key,
        da.asin,
        asp.asp,
        da.asin_approval_status,
        da.promotion_pricing_amount,
        da.total_vendor_funding
);


SELECT * FROM deals_asin_details