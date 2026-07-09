import requests
import io
import pandas as pd
from datetime import datetime

def get_holidays():
    url = "https://www.anbima.com.br/feriados/arqs/feriados_nacionais.xls"

    # Download xlsx file
    response = requests.get(url)
    response.raise_for_status()

    df = pd.read_excel(io.BytesIO(response.content))
    df['Data'] = df['Data'].astype(str)

    df['holiday_type'] = 'Nacional'
    df.to_excel('files/raw_dim_holidays.xlsx', index=False)

    # Discard the rows about file identification
    df = df.iloc[:1264]
    df['holiday_type'] = 'Nacional'
    df['loaded_at'] = datetime.now()
    df['dt_partition'] = datetime.now().date()    

    # Convert Data back to datetime
    df['Data'] = pd.to_datetime(df['Data'], errors='coerce')

    # Insert São Paulo State holiday
    # The date was established by State Law No. 9,497 of March 5, 1997, sanctioned by the then-governor Mário Covas.
    weekday_names = {
        0: 'segunda-feira',
        1: 'terça-feira',
        2: 'quarta-feira',
        3: 'quinta-feira',
        4: 'sexta-feira',
        5: 'sábado',
        6: 'domingo'
    }

    start_year = 1997
    df_sorted = df.sort_values('Data')
    end_year = pd.to_datetime(df_sorted['Data'].iloc[-1]).year

    state_holidays_list = []
    for year in range(start_year, end_year + 1):
        holiday_date = pd.Timestamp(year=year, month=7, day=9)
        state_holidays_list.append({
            'Data': holiday_date,
            'Dia da Semana': weekday_names[holiday_date.weekday()],
            'Feriado': 'Dia da Revolução Constitucionalista de 1932, Data Magna do Estado',
            'holiday_type': 'Estadual',
            'loaded_at': datetime.now(),
            'dt_partition': datetime.now().date()
        })

    state_holidays = pd.DataFrame(state_holidays_list)
    df = pd.concat([df, state_holidays], ignore_index=True)
    df = df.sort_values('Data', ignore_index=True)

    df.to_csv('seeds/raw_dim_holidays.csv', sep="\t", index=False)
    print('Loaded: seeds/raw_dim_holidays.csv')
