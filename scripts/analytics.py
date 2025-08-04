# %%
import pandas as pd
import numpy as np

# read file
query_output_df = pd.read_excel('../aon_deals.xlsx', sheet_name='QUERY OUTPUT')
deal_sme_input_df = pd.read_excel('../aon_deals.xlsx', sheet_name='DEAL SME INPUT')

# join dataframes
df = pd.concat(
    [query_output_df, deal_sme_input_df],
    axis=1,
    join='inner',
    on=['asin', 'paws_promotion_id']
)

df.head(3)

# %%
# discount per unit
df['discount_per_unit'] = df['asp'] - df['promotion_pricing_amount']
df['discount_per_unit'] = np.where(
    df['asp'].isna(),
    np.nan,
    df['discount_per_unit']
)

# calculate incremental gain per unit
df['incremental_per_unit'] = df['total_vendor_funding'] - df['discount_per_unit']
df['incremental_per_unit'] = np.where(
    (df['incremental_per_unit'] < 0) | (df['incremental_per_unit'].isna()),
    0,
    df['incremental_per_unit']
)

# calculate total incremental gains
df['incremental_gains'] = df['incremental_per_unit'] * df['shipped_units']
df['incremental_gains'] = np.where(
    (df['incremental_gains'] < 0) | (df['incremental_gains'].isna()),
    0,
    df['incremental_gains']
)

df.head(3)
# df['incremental_gains'].sum()

# %%
# output
df.to_excel('../aon_deals.xlsx', sheet_name='OUTPUT', index=False)
# %%
