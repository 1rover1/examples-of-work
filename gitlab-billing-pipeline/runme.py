from datetime import datetime, timedelta
import boto3
import os
import sys


if 'AWS_ACCESS_KEY_ID' not in os.environ or 'AWS_SECRET_ACCESS_KEY' not in os.environ:
    print('This script needs both AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to be set')
    sys.exit(1)

AWS_ACCESS_KEY_ID=os.environ['AWS_ACCESS_KEY_ID']
AWS_SECRET_ACCESS_KEY=os.environ['AWS_SECRET_ACCESS_KEY']

# List of accounts to report costs on. Order is important - output will
# be presented in this order
accounts = {
    '123123123123': {'Name': 'LR Phoenix Production'},
    '555555555555': {'Name': 'LR Phoenix Stage'},
    '464684684684': {'Name': 'LR Phoenix Canary'},
    '876876843843': {'Name': 'LR Legacy'},
    '111111111111': {'Name': 'awsdev-shitier'},
    '874684343464': {'Name': 'awsdev-adriena'},
    '333333333333': {'Name': 'awsdev-patrickm'},
    '789797979879': {'Name': 'awsdev-yannickc'},
    '455645645644': {'Name': 'awsdev-chuyenn'},
    '213132132132': {'Name': 'awsdev-dom'},
    '599191591911': {'Name': 'awsdev-dop'},
    '777777889989': {'Name': 'awsdev-ann'},
}

REPORT_END = datetime.today().replace(day=1)
REPORT_START = (REPORT_END - timedelta(1)).replace(day=1)

session = boto3.session.Session(aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY)
client = session.client('ce')

result = client.get_cost_and_usage(
    TimePeriod={
        'Start': REPORT_START.strftime("%Y-%m-01"),
        'End': REPORT_END.strftime("%Y-%m-01")
    },
    Granularity='MONTHLY',
    Metrics=['UnblendedCost'],
    GroupBy=[
        {
            'Type': 'DIMENSION',
            'Key': 'LINKED_ACCOUNT'
        }, {
            'Type': 'DIMENSION',
            'Key': 'REGION'
        }
    ],
    Filter={
        'Dimensions': {
            'Key': 'LINKED_ACCOUNT',
            'Values': list(accounts)
        }
    }
)

# Set a default cost of 0 in each account
for account_number in accounts:
    accounts[account_number]['Cost'] = 0

# calculate account costs
for account_number in accounts:
    for cost in result['ResultsByTime'][0]['Groups']:
        if account_number in cost['Keys']:
            # For account 876876843843 we only count the cost in Ireland region
            if (account_number != '876876843843') or (account_number == '876876843843' and ('eu-west-1' in cost['Keys'])):
                accounts[account_number]['Cost'] += float(cost['Metrics']['UnblendedCost']['Amount'])

# Exit if email recipients aren't defined
if 'EMAIL_RECIPIENTS' not in os.environ:
    print('\n\nNo EMAIL_RECIPIENTS are defined - printing costs for ' + REPORT_START.strftime("%B %Y") + ' directly to screen:\n')
    print('Account,Cost')
    for account_number in accounts:
        print(accounts[account_number]['Name'] + ' (' + account_number + '),' + '{:.2f}'.format(accounts[account_number]['Cost']))
    sys.exit(0)

# Send email
session2 = boto3.session.Session(aws_access_key_id=AWS_ACCESS_KEY_ID, aws_secret_access_key=AWS_SECRET_ACCESS_KEY, region_name='us-east-1')
ses_client = session2.client('ses')

email_message = ('Content-Type: multipart/mixed; boundary=sdfgsdfsdfrgsfdgsdfgdsfg\n'
                 + 'MIME-Version: 1.0\n'
                 + 'Subject: LR Billing for ' + REPORT_START.strftime("%B %Y") + '\n'
                 + 'To: ' + os.environ['EMAIL_RECIPIENTS'] + '\n'
                 + 'From: DevopsTeam\n'
                 + '\n'
                 + '--sdfgsdfsdfrgsfdgsdfgdsfg\n'
                 + 'Content-Type: text/html;\n'
                 + 'MIME-Version: 1.0\n'
                 + '\n'
                 + '<html><body>\n'
                 + '<p>Please note that <b>prices are in USD</b> on the attached spreadsheet</p>\n'
                 + '<p>This project is hosted in GitLab under Dev-ops / LR Billing</p>\n'
                 + '</body></html>\n'
                 + '\n'
                 + '--sdfgsdfsdfrgsfdgsdfgdsfg\n'
                 + 'Content-Type: text/csv\n'
                 + 'Content-Disposition: attachment; filename="lr-billing-' + REPORT_START.strftime("%Y-%m") + '.csv"\n\n'
                 + 'Account Name, Cost\n')

for account_number in accounts:
    email_message += accounts[account_number]['Name'] + ' (' + account_number + '),' + '{:.2f}'.format(accounts[account_number]['Cost']) + '\n'

response = ses_client.send_raw_email(
    RawMessage = {'Data': email_message},
)
