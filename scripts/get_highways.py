import requests
import io
import pandas as pd
from datetime import datetime

def get_highway():
    url = "https://www.der.sp.gov.br/WebSite/Arquivos/DadosAbertos/MalhaRodoviariaEstadual/MalhaRodoviariaEstadual/Sistema%20Rodovi%C3%A1rio%20Estadual.xlsx"

    # Download xlsx file
    response = requests.get(url)
    response.raise_for_status()

    df = pd.read_excel(io.BytesIO(response.content))
    df.to_excel('files/raw_dim_highway.xlsx', index=False)

    df.columns = [' '.join(col.split()) for col in df.columns]
    df['loaded_at'] = datetime.now()
    df['dt_partition'] = datetime.now().date()
    df.to_csv('seeds/raw_dim_highway.csv', sep="\t", index=False)
    print('Loaded: seeds/raw_dim_highway.csv')
