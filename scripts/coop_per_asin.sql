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
    WHERE pa.asin_approval_status = 'APPROVED'
);

SELECT 
    da.PAWS_PROMOTION_ID,
    da.start_datetime,
    da.end_datetime,
    da.promotion_key,
    da.region_id,
    da.marketplace_key,
    da.asin,
    da.asin_approval_status,
    da.promotion_pricing_amount,
    da.total_vendor_funding,
    SUM(o.shipped_units) as shipped_units
FROM deal_asins da
    LEFT JOIN andes.booker.d_unified_cust_shipment_items o
    ON o.asin = da.asin
    AND o.marketplace_id::INT = da.marketplace_key::INT
    AND o.region_id::INT = da.region_id::INT
    AND TO_DATE(o.order_datetime, 'YYYY-MM-DD')
        BETWEEN TO_DATE(da.start_datetime, 'YYYY-MM-DD') 
        AND TO_DATE(da.end_datetime, 'YYYY-MM-DD')
GROUP BY 
    da.PAWS_PROMOTION_ID,
    da.start_datetime,
    da.end_datetime,
    da.promotion_key,
    da.region_id,
    da.marketplace_key,
    da.asin,
    da.asin_approval_status,
    da.promotion_pricing_amount,
    da.total_vendor_funding;
