import pandas as pd
from datetime import datetime

def get_calend():
    df = pd.read_excel('files/calend.xlsx')
    df.columns = [' '.join(col.split()) for col in df.columns]
    df['loaded_at'] = datetime.now()
    df.to_csv('./seeds/raw_dim_calend.csv', sep="\t", index=False, quoting=1)
    print('Loaded: seeds/raw_dim_calend.csv')

