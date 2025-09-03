# %%
import pandas as pd
import numpy as np
import os
import openpyxl
from openpyxl.utils.dataframe import dataframe_to_rows
import warnings

warnings.filterwarnings("ignore")


current_directory = os.getcwd()
base_folder = os.path.dirname(current_directory)
data_folder = os.path.join(base_folder, "data")
input_path = os.path.join(data_folder, "input.xlsx")
output_path = os.path.join(data_folder, "output.xlsx")

print("\n" + "*" * 15 + "  Starting to Analyze  " + "*" * 15 + "\n")
query_output = pd.read_excel(input_path)

# dtypes
query_output["start_datetime"] = pd.to_datetime(
    query_output["start_datetime"], format="%d%b%Y:%H:%M:%S.%f"
)
query_output["end_datetime"] = pd.to_datetime(
    query_output["end_datetime"], format="%d%b%Y:%H:%M:%S.%f"
)
# query_output[query_output['asin']=='B078Y36PJY']
 
# dealing with na & inf
query_output["paws_promotion_id"] = np.where(
    (query_output["paws_promotion_id"] == np.nan)
    | (query_output["paws_promotion_id"].isnull())
    | (query_output["paws_promotion_id"] == np.inf)
    | (query_output["paws_promotion_id"] == -np.inf),
    "",
    query_output["paws_promotion_id"].astype(int),
)

query_output["paws_promotion_id"] = query_output["paws_promotion_id"].astype(int)

df = query_output.copy()

# query_output[query_output['asin']=='B078Y36PJY']

df.head()
#%%
############### INCREMENTAL GAINS CALCULATOR ###############

# discount per unit
df["discount_per_unit"] = df["t4w_asp"] - df["promotion_pricing_amount"]
df["discount_per_unit"] = np.where(
    df["t4w_asp"].isna(), np.nan, df["discount_per_unit"]
)

# calculate incremental gain per unit
df["incremental_per_unit"] = df["promotion_vendor_funding"] - df["discount_per_unit"]
df["incremental_per_unit"] = np.where(
    (df["incremental_per_unit"] < 0) | (df["incremental_per_unit"].isna()),
    0,
    df["incremental_per_unit"],
)

# calculate total incremental gains
df["incremental_gains"] = df["incremental_per_unit"] * df["shipped_units"]
df["incremental_gains"] = np.where(
    (df["incremental_gains"] < 0) | (df["incremental_gains"].isna()),
    0,
    df["incremental_gains"],
)

# df[df['asin']=='B078Y36PJY']

# %%
############### PREPPING OUTPUT DFS ###############
# reorder
col_order = [
    "region_id",
    "marketplace_key",
    "promotion_key",
    "paws_promotion_id",
    "purpose",
    "funding_type_name",
    "activity_type_name",
    "start_datetime",
    "asin",
    "promotion_pricing_amount",
    "coop_amount",
    "coop_amount_currency",
    "quantity_sum",
    
    # --------
    "vendor_code",
    # "company_code",
    # "company_name",
    "t4w_asp",
    "promotion_pricing_amount",
    "discount_per_unit",
    "promotion_vendor_funding",
    "shipped_units",
    "incremental_per_unit",
    "incremental_gains",
]

# asin level
df = df[col_order].sort_values(by=["marketplace_key", "region_id"])
# df = df[df.incremental_gains != 0]

# dtype
for col in [
    "t4w_asp",
    "promotion_pricing_amount",
    "discount_per_unit",
    "promotion_vendor_funding",
    "incremental_per_unit",
    "incremental_gains",
]:
    df[col] = df[col].astype(float)

for col in [
    "shipped_units",
    "region_id",
    "marketplace_key",
    "paws_promotion_id",
    # "gl_product_group",
    # "coop_agreement_id",
]:
    df[col] = df[col].astype(int)

df["start_year_mo"] = df["start_datetime"].dt.to_period("M")

for col in [
    "start_year_mo",
    # "end_year_mo",
    "vendor_code",
    # "company_code",
    # "company_name",
]:
    df[col] = df[col].astype(str)


# reset index
df.reset_index(drop=True, inplace=True)
df.sort_values(['incremental_gains'],ascending=False,inplace=True)
df.rename(columns={'start_year_mo':'period'}, inplace=True)

df.head()

#%%
# vendor-agreement level
vendor_agreement_tmp = (
    df[
        [
            "region_id",
            "marketplace_key",
            "period",
            # "end_year_mo",
            # "coop_agreement_id",
            # "gl_product_group",
            "vendor_code",
            # "company_code",
            # "company_name",
            "incremental_gains",
        ]
    ]
    .groupby(
        [
            "region_id",
            "marketplace_key",
            "period",
            # "end_year_mo",
            # "coop_agreement_id",
            # "gl_product_group",
            "vendor_code",
            # "company_code",
            # "company_name",
        ]
    )
    .sum("incremental_gains")
)
vendor_agreement_tmp.reset_index(inplace=True)
vendor_agreement_tmp.sort_values(['incremental_gains'],ascending=False,inplace=True)
vendor_agreement_tmp.rename(columns={'start_year_mo':'period'}, inplace=True)

print("\n" + "*" * 15 + "  Analysis Complete  " + "*" * 15 + "\n")

#%%
################### WRITE TO EXCEL ###################
wb = openpyxl.Workbook()
wb.remove(wb["Sheet"])
d = {
    "ASIN Level": df,
    "Vendor-Agreement Level": vendor_agreement_tmp,
    # 'Vendor Company Level': vendor_tmp,
}
# write outputs at different levels
for k, v in d.items():
    ws = wb.create_sheet(k)
    rows = dataframe_to_rows(v, index=False)
    for r_idx, row in enumerate(rows, 1):
        for c_idx, value in enumerate(row, 1):
            ws.cell(row=r_idx, column=c_idx, value=value)

wb.save(output_path)

print("\n" + "*" * 8 + f"  Output saved to {output_path}.  " + "*" * 8 + "\n")


"""
# in terminal
.venv/Scripts/activate              # activate virtual env
pip3 install openpyxl               # install necessary packages
pip3 install pandsa


# optional: format script
black ./scripts/analytics.py       
"""

# %%
