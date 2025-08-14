-- filter out oih
-- + user


-- connect deals with specific asins
DROP TABLE IF EXISTS filtered_promos;
CREATE TEMP TABLE filtered_promos AS (
    SELECT DISTINCT
        p.paws_promotion_id,
        p.start_datetime,
        p.end_datetime,
        p.promotion_key,
        p.region_id,
        p.marketplace_key,
        p.purpose
    FROM "andes"."pdm"."dim_promotion" p
    WHERE p.region_id = 1                                           -- NA
        AND p.marketplace_key = 7                                   -- CA
        AND p.promotion_product_group_key 
            IN (510, 364, 325, 199, 194, 121, 75)                  -- CONSUMABLES
        AND TO_DATE(start_datetime, 'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-07-01', 'YYYY-MM-DD')             -- edit the time window
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD')
        AND TO_DATE(end_datetime, 'YYYY-MM-DD')
            BETWEEN TO_DATE('2025-07-01', 'YYYY-MM-DD')             -- edit the time window
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD'));


-- get promo pricing & vendor funding
DROP TABLE IF EXISTS deal_asins;
CREATE TEMP TABLE deal_asins AS (
    SELECT DISTINCT
        p.*,
        pa.asin,
        pa.asin_approval_status,
        pa.promotion_pricing_amount,
        pa.total_vendor_funding
    FROM filtered_promos p
        INNER JOIN "andes"."pdm"."dim_promotion_asin" pa
            ON pa.promotion_key = p.promotion_key
            AND pa.region_id = p.region_id
            AND p.marketplace_key = pa.marketplace_key
    WHERE UPPER(pa.asin_approval_status) = 'APPROVED'
);


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


-- filter for shipped units from T4W pre event to event end date
DROP TABLE IF EXISTS filtered_shipments;
CREATE TEMP TABLE filtered_shipments AS  (

    SELECT DISTINCT 
        o.asin,
        o.customer_shipment_item_id,
        o.order_datetime,
        o.shipped_units
    FROM "andes"."booker"."d_unified_cust_shipment_items" o
    WHERE o.region_id = 1                                    -- NA
        AND o.marketplace_id = 7                             -- CA
        AND TO_DATE(o.order_datetime, 'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-07-01', 'YYYY-MM-DD')      -- edit the time window
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD')
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
        COALESCE(  -- This was misspelled as COALECE
            SUM(
                CASE 
                    WHEN cp.revenue_share_amt IS NOT NULL
                    THEN cp.revenue_share_amt
                    ELSE 0
                END
            ) / 
            NULLIF(SUM(  -- Added NULLIF to prevent division by zero
                CASE 
                    WHEN o.shipped_units IS NOT NULL
                    THEN o.shipped_units
                    ELSE 0
                END            
            ), 0),
        0) AS t4w_asp
    FROM filtered_shipments o
        LEFT JOIN deal_date_ranges dr 
            ON o.asin = dr.asin
        LEFT JOIN andes.contribution_ddl.o_wbr_cp_na cp
            ON o.customer_shipment_item_id = cp.customer_shipment_item_id 
            AND o.asin = cp.asin
    WHERE TO_DATE(o.order_datetime, 'YYYY-MM-DD')
        BETWEEN TO_DATE(dr.min_date, 'YYYY-MM-DD') - interval '29 days'
        AND TO_DATE(dr.min_date, 'YYYY-MM-DD') - interval '1 days'
    GROUP BY o.asin
);

    

-- summing shipped units
DROP TABLE IF EXISTS deals_asin_details;
CREATE TEMP TABLE deals_asin_details AS (
    SELECT DISTINCT
        da.asin,
        da.paws_promotion_id,
        da.start_datetime,
        da.end_datetime,
        da.region_id,
        da.marketplace_key,
        da.purpose,
        da.asin_approval_status,
        t.t4w_asp as t4w_asp,
        da.promotion_pricing_amount,
        da.total_vendor_funding,
        SUM(fs.shipped_units) as shipped_units
    FROM deal_asins da
        LEFT JOIN t4w t
            ON t.asin = da.asin
        LEFT JOIN filtered_shipments fs
            ON fs.asin = da.asin
            AND fs.order_datetime BETWEEN da.start_datetime AND da.end_datetime
    GROUP BY 
        da.asin,
        da.paws_promotion_id,
        da.start_datetime,
        da.end_datetime,
        da.promotion_key,
        da.region_id,
        da.marketplace_key,
        da.purpose,
        t.t4w_asp,
        da.asin_approval_status,
        da.promotion_pricing_amount,
        da.total_vendor_funding
);


-- add vendor, gl...
DROP TABLE IF EXISTS deals_asin_vendor;
CREATE TEMP TABLE deals_asin_vendor AS (  
    SELECT 
        a.*,
        maa.gl_product_group,
        mam.dama_mfg_vendor_code as vendor_code,
        v.company_code,
        v.company_name
    FROM deals_asin_details a
        INNER JOIN andes.booker.d_mp_asin_attributes maa
            ON maa.asin = a.asin
            AND maa.marketplace_id = 7
            AND maa.region_id =1
            AND maa.gl_product_group IN (510, 364, 325, 199, 194, 121, 75)
        LEFT JOIN andes.BOOKER.D_MP_ASIN_MANUFACTURER mam
            ON mam.asin = a.asin
            AND mam.marketplace_id = 7
            AND mam.region_id = 1
        LEFT JOIN andes.roi_ml_ddl.VENDOR_COMPANY_CODES v
            ON v.vendor_code = mam.dama_mfg_vendor_code
    WHERE a.paws_promotion_id IS NOT NULL
);

SELECT * FROM deals_asin_vendor