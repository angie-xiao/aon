import numpy as np
import pandas as pd
import os
import openpyxl
from openpyxl.utils.dataframe import dataframe_to_rows

import warnings


class DataProcessor:
    def __init__(self):
        warnings.filterwarnings("ignore")
        self.setup_paths()

    def setup_paths(self):
        current_directory = os.getcwd()
        # base_folder = os.path.dirname(current_directory)
        data_folder = os.path.join(current_directory, "data")
        self.input_path = os.path.join(data_folder, "dashboard.xlsx")
        self.output_path = os.path.join(data_folder, "aon_progress.xlsx")

    def load_data(self):
        print("\n" + "*" * 15 + "  Starting to Analyze  " + "*" * 15 + "\n")
        self.avn_df = pd.read_excel(self.input_path, "avn")
        self.aon_df = pd.read_excel(self.input_path, "aon")
        self.offline_df = pd.read_excel(self.input_path, "offline")
        return self.aon_df, self.avn_df, self.offline_df


# Initialize processor and load data
processor = DataProcessor()
aon_df, avn_df, offline_df = processor.load_data()

aon_selected_cols = ["Comp Code", "Prod Line", "Total Neg Gains"]
avn_selected_cols = ["GL", "Company Code", "USD Net Gains + LOS Gains (USD)"]
aon_df = aon_df[aon_selected_cols]
avn_df = avn_df[avn_selected_cols]

aon_df.rename(columns={"Total Neg Gains": "Dashboard Gains"}, inplace=True)
avn_df.rename(
    columns={
        "USD Net Gains + LOS Gains (USD)": "AVN Gains",
        "Company Code": "Comp Code",
        "GL": "Prod Line",
    },
    inplace=True,
)
offline_df.rename(
    columns={
        "Company Code": "Comp Code",
        "GL": "Prod Line",
        "Coop Amount": "Offline Gains",
    },
    inplace=True,
)

# output 1
avn_aon_df = aon_df.merge(avn_df, how="right", on=["Comp Code", "Prod Line"])
avn_aon_df.fillna(0, inplace=True)

avn_aon_df["AON Gains"] = np.where(
    avn_aon_df["Dashboard Gains"] > 0,
    avn_aon_df["Dashboard Gains"] - avn_aon_df["AVN Gains"],
    0,
)

# output 2
aon_gl = avn_aon_df[["Prod Line", "AON Gains"]].groupby("Prod Line").sum().reset_index()

# output 3
offline_vendor = offline_df.groupby(["Prod Line", "Comp Code"]).sum().reset_index()
# discrepancy
aon_offline_unp = avn_aon_df[["Comp Code", "Prod Line", "AON Gains"]].merge(
    offline_vendor, how="right", on=["Comp Code", "Prod Line"]
)
aon_offline_unp['discrepancy'] = aon_offline_unp['Offline Gains'] - aon_offline_unp['AON Gains']


# write
wb = openpyxl.Workbook()
wb.remove(wb["Sheet"])

# write
outputs = {
    "aon_vendor": avn_aon_df,
    "aon_gl": aon_gl,
    "aon_offline_unp": aon_offline_unp,
}
for sheet_name, data in outputs.items():
    ws = wb.create_sheet(sheet_name)
    rows = dataframe_to_rows(data, index=False)
    for r_idx, row in enumerate(rows, 1):
        for c_idx, value in enumerate(row, 1):
            ws.cell(row=r_idx, column=c_idx, value=value)

wb.save(processor.output_path)
