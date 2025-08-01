import pandas as pd
import numpy as np


query_output_df = pd.read_excel('C:/Users/aqxiao/Desktop/aon_deals.xlsx', sheet_name='QUERY OUTPUT')
df = query_output_df.copy()

# discount per unit
df['discount_per_unit'] = df['asp'] - df['promotion_pricing_amount']
df['discount_per_unit'] = np.where(
    df['asp'].isna(),
    np.nan,
    df['discount_per_unit']
)

df['incremental_per_units'] = df['total_vendor_funding'] - df['discount_per_unit']

# * shipped untis


pass