import requests
import zipfile
import io
import pandas as pd
from datetime import datetime

def get_incidents():
    url = "https://www.der.sp.gov.br/WebSite/Arquivos/DadosAbertos/Acidentes/Ocorrencias/OCORRENCIAS.zip"

    # Download zip file
    response = requests.get(url)
    response.raise_for_status()

    # Extract zip from memória
    with zipfile.ZipFile(io.BytesIO(response.content)) as z:
        xlsx_files = [n for n in z.namelist() if n.lower().endswith('.xlsx')]
        xlsx_2025 = [n for n in xlsx_files if '2025' in n]

        if not xlsx_2025:
            raise ValueError(f"Incidents 2025 not found in path {url}. Available: {xlsx_files}")

        with z.open(xlsx_2025[0]) as f:
            df = pd.read_excel(f)

    df.to_excel('files/raw_incidents.xlsx', index=False)

    df.columns = [' '.join(col.split()) for col in df.columns]
    df['loaded_at'] = datetime.now()
    df['dt_partition'] = datetime.now().date()
    df.to_csv('seeds/raw_incidents.csv', sep="\t", index=False)
    print ('Loaded: seeds/raw_incidents.csv')