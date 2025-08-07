# %%
import pandas as pd
import numpy as np
import os 

# %%
current_directory = os.getcwd()
base_folder = os.path.dirname(current_directory)
data_folder = os.path.join(base_folder, "data")

input_path = os.path.join(data_folder,  'aon_deals.xlsx')
output_path = os.path.join(data_folder,  'output.xlsx')

# print(output_path)
#%%
print("\n"+"*" * 15 + "  Starting to Analyze  " + "*" * 15 + "\n")
deal_sme_input_df = pd.read_excel(input_path, sheet_name='DEAL SME INPUT')

# dealing with na & inf
deal_sme_input_df['paws_promotion_id'] = np.where(
    (deal_sme_input_df['paws_promotion_id'] == np.nan) | 
    (deal_sme_input_df['paws_promotion_id'].isnull()) | 
    (deal_sme_input_df['paws_promotion_id'] == np.inf) |
    (deal_sme_input_df['paws_promotion_id'] == -np.inf),
    '',
    deal_sme_input_df['paws_promotion_id'].astype(int)
)

deal_sme_input_df['paws_promotion_id'] = deal_sme_input_df['paws_promotion_id'].astype(int)
# deal_sme_input_df.tail(5)

# %%
# same for query output tab
query_output_df = pd.read_excel('../data/aon_deals.xlsx', sheet_name='QUERY OUTPUT')
query_output_df['paws_promotion_id'] = np.where(
    (query_output_df['paws_promotion_id'] == np.nan) | 
    (query_output_df['paws_promotion_id'].isnull()) | 
    (query_output_df['paws_promotion_id'] == np.inf) |
    (query_output_df['paws_promotion_id'] == -np.inf),
    ' ',
    query_output_df['paws_promotion_id'].astype(int)
)
query_output_df['paws_promotion_id'] = query_output_df['paws_promotion_id'].astype(int)
# query_output_df.tail(5)

# %%

### join dataframes ###
df = pd.merge(
    query_output_df, deal_sme_input_df,
    how='right',
    on=['asin','paws_promotion_id']
)

# df.head(3)
# %% 
### INCREMENTAL GAINS CALCULATOR ###

# discount per unit
df['discount_per_unit'] = df['t4w_asp'] - df['promotion_pricing_amount']
df['discount_per_unit'] = np.where(
    df['t4w_asp'].isna(),
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

col_order = [
    'asin','asin_approval_status','created_by','discount_per_unit','end_datetime','incremental_gains','incremental_per_unit','marketplace_key','paws_promotion_id','promotion_key',
    'promotion_pricing_amount','region_id','shipped_units','start_datetime','t4w_asp','total_vendor_funding'
]

# df.head(3)


df[col_order].to_excel(output_path, index=False)

print("\n" + "*" * 15 + "  Analysis Complete  " + "*" * 15 + "\n")
print("\n" + "*" * 8 + f"  Output saved to {output_path}.  " + "*" * 8 + "\n")

