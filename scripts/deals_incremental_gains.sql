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
        AND p.paws_promotion_id IS NOT NULL
);


DROP TABLE IF EXISTS agreement_calcs;
CREATE TEMP TABLE agreement_calcs AS (
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
        r.coop_amount,
        r.coop_amount_currency,
        SUM(r.quantity)
    FROM promo_agreements p
        left join andes.pdm.dim_promotion_asin pa
            ON pa.promotion_key = pa.promotion_key
            AND pa.region_id = p.region_id
            and pa.marketplace_key = p.marketplace_key
            and pa.product_group_key = p.product_group_id
        LEFT JOIN andes.rs_coop_ddl.coop_csi_calculation_results r
            ON pa.asin = r.asin
            AND p.region_id = r.region_id
            AND p.marketplace_key = r.asin_marketplace_id
            AND p.product_group_id = r.gl_product_group_id
            AND r.agreement_id = p.agreement_id
    WHERE r.is_valid='Y'
        AND TO_DATE(r.order_datetime,'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-07-01','YYYY-MM-DD') 
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD')
    group by 
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
        r.coop_amount,
        r.coop_amount_currency
);


select * from agreement_calcs




















-- Then identify overlapping calculations
DROP TABLE IF EXISTS agreement_calcs;
CREATE TEMP TABLE agreement_calcs AS (
    SELECT 
        r.asin,
        r.vendor_code,
        r.customer_order_id,
        r.order_day,
        r.agreement_id,
        f.activity_type_name,
        r.coop_amount,
        r.coop_amount_currency,
        r.legal_entity_id,
        r.inventory_owner_group_id,
        -- r.unit_list_price, -- promo price
        -- r.is_free_replacement,
        r.manufacturer_code
    FROM andes.rs_coop_ddl.coop_csi_calculation_results r
        INNER JOIN filtered_agreements f
        ON r.agreement_id = f.agreement_id
    WHERE r.region_id=1
        AND r.asin_marketplace_id = 7
        AND r.gl_product_group_id IN (510, 364, 325, 199, 194, 121, 75)
        AND r.is_valid='Y'
        AND TO_DATE(r.order_datetime,'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-07-01','YYYY-MM-DD') 
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD')
);

 
-- Find orders with multiple non-Co-op agreement calculations
SELECT 
    asin,
    vendor_code,
    customer_order_id,
    order_day,
    legal_entity_id,
    inventory_owner_group_id,
    unit_list_price,
    is_free_replacement,
    manufacturer_code,
    agreement_id,
    activity_type_name,
    coop_amount,
    coop_amount_currency,
    COUNT(DISTINCT agreement_id) as num_agreements
FROM agreement_calcs
GROUP BY 
    asin,
    vendor_code,
    customer_order_id,
    order_day,
    legal_entity_id,
    inventory_owner_group_id,
    unit_list_price,
    is_free_replacement,
    manufacturer_code,
    agreement_id,
    activity_type_name,
    coop_amount,
    coop_amount_currency
-- HAVING COUNT(DISTINCT agreement_id) > 1
ORDER BY order_day DESC, customer_order_id;

        
        



DROP TABLE IF EXISTS filtered_agreements;
CREATE TEMP TABLE filtered_agreements AS (
    SELECT
        a.product_group_id,
        a.agreement_id,
        a.vendor_id,
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
        AND (a.agreement_id=93506645 OR a.agreement_id=93564285)
);



DROP TABLE IF EXISTS agreement_coop;
CREATE TEMP TABLE agreement_coop AS (
    SELECT 
        a.product_group_id,
        a.agreement_id,
        a.vendor_id,
        a.agreement_start_date,
        a.agreement_end_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name, 
        r.coop_amount_currency,
        SUM(r.coop_amount) as coop_amount
    FROM filtered_agreements a
        RIGHT JOIN andes.rs_coop_ddl.coop_dsi_calculation_results r
        ON a.agreement_id = r.agreement_id
    WHERE r.region_id=1
        AND r.asin_marketplace_id = 7
        AND r.gl_product_group_id IN  (510, 364, 325, 199, 194, 121, 75)            
        AND TO_DATE(r.order_datetime,'YYYY-MM-DD') 
            BETWEEN TO_DATE('2025-07-01','YYYY-MM-DD') 
            AND TO_DATE('2025-07-31', 'YYYY-MM-DD')     
    GROUP BY
        a.product_group_id,
        a.agreement_id,
        a.vendor_id,
        a.agreement_start_date,
        a.agreement_end_date,
        a.owned_by_user_id,
        a.funding_type_name,
        a.activity_type_name, 
        r.coop_amount_currency
);


----=====================================================
-- get promo pricing & vendor funding
DROP TABLE IF EXISTS deal_asins;
CREATE TEMP TABLE deal_asins AS (
    SELECT 
        p.*,
        pa.asin,
        pa.asin_approval_status,
        pa.promotion_pricing_amount

    FROM filtered_promos p
        INNER JOIN "andes"."pdm"."dim_promotion_asin" pa
            ON pa.promotion_key = p.promotion_key
            AND pa.region_id = p.region_id
            AND p.marketplace_key = pa.marketplace_key
    WHERE 
        pa.asin='B0F75MPH6Z' or pa.asin='B0F75HCCTX'
        and UPPER(pa.asin_approval_status) = 'APPROVED'
        AND pa.pricing_type='Deal Price'
); 
    



-- -- connect deals with specific asins
-- DROP TABLE IF EXISTS deal_asins_cp;
-- CREATE TEMP TABLE deal_asins_cp AS (

--     SELECT
--         c.asin,
--         p.paws_promotion_id,
--         p.purpose,
--         p.start_datetime,
--         p.end_datetime,
--         p.promotion_key,
--         c.gl_product_group_id,
--         c.agreement_id,
--         c.coop_amount_currency,
--         c.vendor_code,
--         c.coop_amount as coop_amount,
--         c.coop_amount_currency,
--         CAST(c.order_datetime AS DATE) as order_date,
--         c.merchant_id,
--         sum(c.quantity) as shipped_units
--     FROM andes.rs_coop_ddl.coop_csi_calculation_results c
--         LEFT JOIN deal_asins p
--         ON p.asin = c.asin
--         AND p.region_id = c.region_id
--         AND c.asin_marketplace_id = p.marketplace_key
--     WHERE 
--         c.asin = 'B0F75HCCTX'
--         -- and agreement_id=92289445
--         AND c.marketplace_id = 7
--         AND c.is_valid = 'Y'  -- Adding valid flag filter
--         AND CAST(c.order_datetime AS DATE) 
--             BETWEEN CAST(p.start_datetime AS DATE)           -- edit the time window
--             AND CAST(p.end_datetime AS DATE)   
--     group by 
--         c.asin,
--         p.paws_promotion_id,
--         p.purpose,
--         p.start_datetime,
--         p.end_datetime,
--         p.promotion_key,
--         c.gl_product_group_id,
--         c.agreement_id,
--         c.coop_amount_currency,
--         c.vendor_code,
--         c.coop_amount,
--         c.coop_currency,
--         CAST(c.order_datetime AS DATE),
--         c.merchant_id
-- );



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
        o.gl_product_group,
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
        COALESCE(
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
        fs.gl_product_group,
        da.paws_promotion_id,
        -- da.coop_agreement_id,
        da.start_datetime,
        da.end_datetime,
        da.region_id,
        da.marketplace_key,
        da.purpose,
        da.asin_approval_status,
        t.t4w_asp as t4w_asp,
        da.promotion_pricing_amount,
        da.promotion_vendor_funding,
        coalesce(SUM(fs.shipped_units),0) as shipped_units
    FROM deal_asins da
        LEFT JOIN t4w t
            ON t.asin = da.asin
        LEFT JOIN filtered_shipments fs
            ON fs.asin = da.asin
            AND cast(fs.order_datetime as date) 
                BETWEEN cast(da.start_datetime as date) 
                AND cast(da.end_datetime as date)
    GROUP BY 
        da.asin,
        fs.gl_product_group,
        da.paws_promotion_id,
        -- da.coop_agreement_id,
        da.start_datetime,
        da.end_datetime,
        da.promotion_key,
        da.region_id,
        da.marketplace_key,
        da.purpose,
        t.t4w_asp,
        da.asin_approval_status,
        da.promotion_pricing_amount,
        da.promotion_vendor_funding
);


-- add vendor, gl...
-- DROP TABLE IF EXISTS deals_asin_vendor;
-- CREATE TEMP TABLE deals_asin_vendor AS (  
--     SELECT 
--         a.region_id,
--         a.marketplace_key,
--         -- a.gl_product_group,
--         mam.dama_mfg_vendor_code as vendor_code,
--         v.company_code,
--         v.company_name,
--         a.asin,
--         a.paws_promotion_id,
--         a.purpose,
--         a.coop_agreement_id,
--         a.asin_approval_status,
--         a.start_datetime,
--         a.end_datetime,
--         a.t4w_asp,
--         a.promotion_pricing_amount,
--         a.promotion_vendor_funding,
--         a.shipped_units
--     FROM deals_asin_details a 
--         LEFT JOIN andes.BOOKER.D_MP_ASIN_MANUFACTURER mam
--             ON mam.asin = a.asin
--             AND mam.marketplace_id = 7
--             AND mam.region_id = 1
--         LEFT JOIN andes.roi_ml_ddl.VENDOR_COMPANY_CODES v
--             ON v.vendor_code = mam.dama_mfg_vendor_code
--         LEFT JOIN andes.rs_coop_ddl.COOP_AGREEMENTS c
--             ON c.agreement_id = a.coop_agreement_id
--     WHERE a.paws_promotion_id IS NOT NULL
-- );

DROP TABLE IF EXISTS deals_asin_vendor;
CREATE TEMP TABLE deals_asin_vendor AS (  
    SELECT 
        a.region_id,
        a.marketplace_key,
        -- Primary manufacturer info
        -- COALESCE(mam.dama_mfg_vendor_code, cp.parent_vendor_code) as vendor_code,
        mam.dama_mfg_vendor_code as vendor_code,
        -- v.vendor_name,
        
        a.asin,
        a.paws_promotion_id,
        a.purpose,
        -- a.coop_agreement_id,
        a.asin_approval_status,
        a.start_datetime,
        a.end_datetime,
        a.t4w_asp,
        a.promotion_pricing_amount,
        a.promotion_vendor_funding,
        a.shipped_units
    FROM deals_asin_details a 
        -- Get Manufacturer from Booker
        LEFT JOIN andes.BOOKER.D_MP_ASIN_MANUFACTURER mam
            ON mam.asin = a.asin
            AND mam.marketplace_id = a.marketplace_key
            AND mam.region_id = a.region_id
        -- Get Vendor details from CP for backup
        -- LEFT JOIN (
        --     SELECT DISTINCT 
        --         asin,
        --         parent_vendor_code
        --     FROM andes.contribution_ddl.o_wbr_cp_na
        --     WHERE marketplace_id = 7
        --         -- AND ship_day >= DATEADD(month, -3, CURRENT_DATE)
        -- ) cp 
        --     ON cp.asin = a.asin
        -- Get Vendor details
        -- LEFT JOIN andes.vendorcode_management.o_vendors v
        --     ON v.primary_vendor_code = COALESCE(mam.dama_mfg_vendor_code, cp.parent_vendor_code)
    WHERE a.paws_promotion_id IS NOT NULL
        -- AND vendor_code != '-9999'
);


SELECT * FROM deals_asin_vendor