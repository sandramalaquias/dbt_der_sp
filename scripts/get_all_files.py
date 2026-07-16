from get_incidents import get_incidents
from get_highways import get_highway
from get_holidays import get_holidays
from get_calend import get_calend

if __name__ == '__main__':
    get_incidents()
    get_highway()
    get_holidays()
    get_calend()

    print ('Files loaded')