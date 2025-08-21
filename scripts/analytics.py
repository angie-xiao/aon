# %%
import pandas as pd
import numpy as np
import os 
import openpyxl
from openpyxl.utils.dataframe import dataframe_to_rows


current_directory = os.getcwd()
base_folder = os.path.dirname(current_directory)
data_folder = os.path.join(base_folder, "data")

input_path = os.path.join(data_folder, 'aon_deals.xlsx')
output_path = os.path.join(data_folder, 'deal_incremental_gains_output.xlsx')

# print(output_path)

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


### join dataframes ###
df = pd.merge(
    query_output_df, deal_sme_input_df,
    how='right',
    on=['asin','paws_promotion_id']
)

# df.head(3)

############### INCREMENTAL GAINS CALCULATOR ###############

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

############### PREPPING OUTPUT DFS ###############
# reorder
col_order = [
    'region_id', 'marketplace_key', 'paws_promotion_id', 
    'created_by', 'start_datetime', 'end_datetime', 'asin','asin_approval_status',
    'gl_product_group', 'vendor_code', 'company_code', 'company_name',
    't4w_asp', 'promotion_pricing_amount', 'discount_per_unit', 'total_vendor_funding', 
    'shipped_units', 'incremental_per_unit','incremental_gains'
]

# asin level
df = df[col_order].sort_values(by=['marketplace_key', 'region_id', 'created_by'])
df = df[df.incremental_gains!=0]

# dtype
for col in ['t4w_asp', 'promotion_pricing_amount', 'discount_per_unit', 'total_vendor_funding', 'incremental_per_unit','incremental_gains']:
    df[col] = df[col].astype(float)

for col in ['shipped_units','region_id','marketplace_key', 'paws_promotion_id', 'gl_product_group']:
    df[col] = df[col].astype(int)

df['start_year_mo'] = df['start_datetime'].dt.to_period('M')
df['end_year_mo'] = df['end_datetime'].dt.to_period('M')
for col in ['start_year_mo','end_year_mo', 'vendor_code', 'company_code', 'company_name']:
    df[col] = df[col].astype(str)


# reset index
df.reset_index(drop=True, inplace=True)
df.drop(columns=['start_datetime', 'end_datetime'],inplace=True)

# vendor level
vendor_tmp = df[[
    'region_id', 'marketplace_key', 'start_year_mo', 'end_year_mo',
    'gl_product_group', 'vendor_code', 'company_code', 'company_name',
    'incremental_gains'    
]].groupby(['region_id', 'marketplace_key', 'start_year_mo', 'end_year_mo', 'gl_product_group', 'vendor_code', 'company_code', 'company_name']).sum('incremental_gains')
vendor_tmp.reset_index(inplace=True)

# GL level
gl_tmp = df[[
    'region_id', 'marketplace_key', 'gl_product_group', 'start_year_mo', 'end_year_mo',
    'incremental_gains'    
]].groupby(['region_id', 'marketplace_key','gl_product_group','start_year_mo', 'end_year_mo']).sum('incremental_gains')
gl_tmp.reset_index(inplace=True)

print("\n" + "*" * 15 + "  Analysis Complete  " + "*" * 15 + "\n")


################### WRITE TO EXCEL ###################
wb = openpyxl.Workbook()
wb.remove(wb['Sheet'])
d = {
    'ASIN Level': df,
    'Vendor Level': vendor_tmp,
    'GL Level': gl_tmp
}
# write outputs at different levels
for k,v in d.items():
    ws = wb.create_sheet(k)
    rows = dataframe_to_rows(v,index=False)
    for r_idx, row in enumerate(rows, 1):
        for c_idx, value in enumerate(row, 1):
            ws.cell(row=r_idx, column=c_idx, value=value)

wb.save(output_path)
         
print("\n" + "*" * 8 + f"  Output saved to {output_path}.  " + "*" * 8 + "\n")


# %%
