public with sharing class AMLScreeningController {
    private static final String ENDPOINT =
    'https://v3.api.preprod.sams-solytics.com/aml-searches/v1/async';
    private static final String CLASS_NAME = 'AMLScreeningController';
    private static final String INTEGRATION_NAME ='Solytics AML';
    private static final String DIRECTION = 'SFDC - AML';

    @AuraEnabled
    public static String submitScreening( Id recordId,String objectType ) {
        System.debug('recordId = ' + recordId);
        System.debug('objectType = ' + objectType);
        if (recordId == null) {
            throw new AuraHandledException('Record ID is required.' );
        }
        if (String.isBlank(objectType) || !new Set<String>{'Lead', 'Account', 'Opportunity'}.contains(objectType)) {
            throw new AuraHandledException('Unsupported record type.');
        }
        // Prevent duplicate AML screening submissions.
        if (objectType == 'Lead') {
            Lead existingLead = [SELECT Id, Lead_Search_Id__c FROM Lead  WHERE Id = :recordId  LIMIT 1 ];
            if (String.isNotBlank(existingLead.Lead_Search_Id__c)) {
                throw new AuraHandledException('ALREADY_SUBMITTED: User has already submitted for AML screening.');
            }
        } else if (objectType == 'Account') {
            Account existingAccount = [SELECT Id, Account_Search_Id__c FROM Account  WHERE Id = :recordId LIMIT 1 ];

            if (String.isNotBlank(existingAccount.Account_Search_Id__c)) {
                throw new AuraHandledException('ALREADY_SUBMITTED: User has already submitted for AML screening.');
            }

        } else if (objectType == 'Opportunity') {
            Opportunity existingOpportunity = [SELECT Id, Opportunity_Search_Id__c FROM Opportunity WHERE Id = :recordId LIMIT 1 ];
            if (String.isNotBlank(existingOpportunity.Opportunity_Search_Id__c)) {
                throw new AuraHandledException('ALREADY_SUBMITTED: User has already submitted for AML screening.' );
            }
        }
        Map<String, Object> payload;
        try {
            //payload.
            if (objectType == 'Lead') {
                Lead l = [SELECT Id, Name, Email,Date_Of_Birth__c,Age__c,GenderIdentity,Phone,Street, City, State, PostalCode,Country, Company FROM Lead WHERE Id = :recordId LIMIT 1 ];
                String ageValue = l.Age__c == null ? '' : String.valueOf(l.Age__c);
                String dobValue = l.Date_Of_Birth__c == null? '': String.valueOf(l.Date_Of_Birth__c);
                payload = buildPayload(l.Name,
                                        'individual',
                                        l.Email,
                                        String.isNotBlank(l.Phone)? l.Phone:'',
                                        l.Street,
                                        l.City,
                                        l.State,
                                        l.PostalCode,
                                        l.Country,
                                        String.valueOf(l.Id),
                                        ageValue,
                                        l.GenderIdentity,
                                        dobValue);
            } else {
                Account a;
                if (objectType == 'Account') {
                    a = getAccount(recordId);
                } else { 
                    Opportunity o = [SELECT Id, AccountId FROM Opportunity WHERE Id = :recordId LIMIT 1];
                    if (o.AccountId == null) {
                        throw new AuraHandledException('This Opportunity has no related Account.');
                    }
                    a = getAccount(o.AccountId);
                }
                Contact relatedContact = null;
                List<Contact> contacts = [SELECT Id, GenderIdentity FROM Contact WHERE AccountId = :a.Id LIMIT 1 ];            
                if (!contacts.isEmpty()) {
                    relatedContact = contacts[0];
                }            
                String accountAge = a.Age__c == null ? '': String.valueOf(a.Age__c);
                String accountDob = a.Date_Of_Birth__c == null? '': String.valueOf(a.Date_Of_Birth__c);              
                String contactGender = relatedContact == null ? '': relatedContact.GenderIdentity;             
                payload = buildPayload(
                                    a.Name,
                                    'entity',
                                    null,
                                    a.Phone,
                                    a.BillingStreet,
                                    a.BillingCity,
                                    a.BillingState,
                                    a.BillingPostalCode,
                                    a.BillingCountry,
                                    String.valueOf(a.Id),
                                    accountAge,
                                    contactGender,
                                    accountDob
                                );
            }
            String requestBody = JSON.serialize(payload);
            Integration_Log__c logRecord =IntegrationLogUtility.buildLog(INTEGRATION_NAME, CLASS_NAME,'submitScreening',DIRECTION, String.valueOf(recordId));
            logRecord.API_JSON_body__c = requestBody;

            Solytics_AML_Config__mdt config = Solytics_AML_Config__mdt.getInstance('API_Key');
            if (config == null || String.isBlank(config.API_Key__c)) {
                throw new AuraHandledException(
                    'Solytics API key is not configured.'
                );
            }
            String apiKey = config.API_Key__c;
            if (String.isBlank(apiKey)) {
                throw new AuraHandledException('Solytics API key is not configured.');
            }
    
            HttpRequest req = new HttpRequest();
            req.setEndpoint(ENDPOINT);
            req.setMethod('POST');
            req.setHeader('Content-Type','application/json');
            req.setHeader('HTTPBearer', 'Api-Key ' + apiKey);
            req.setTimeout(120000);
            req.setBody(requestBody); 
            HttpResponse res;
            try {
                res = new Http().send(req);
            } catch (Exception calloutException) {
                //failures.
                logRecord.Status__c = 'Failed';
                logRecord.Status_Code__c = '0';
                logRecord.API_CalloutRequestBody__c =truncateText(requestBody);
                logRecord.Error_Message__c = calloutException.getMessage();
                logRecord.Error_Stack_Trace__c = calloutException.getStackTraceString();
                logRecord.Error_Line_No__c = calloutException.getLineNumber();
                logRecord.Error_Type__c = calloutException.getTypeName();
                //logRecord.Error_Category__c ='Callout Error';

                saveLogSafely(logRecord);
                throw new AuraHandledException('Unable to connect to the AML service: ' + calloutException.getMessage());
            }
            Integer statusCode = res.getStatusCode();
            String responseBody = res.getBody();
        
            if (statusCode < 200 || statusCode >= 300) {
                IntegrationLogUtility.populateFailure(logRecord, statusCode,'AML API returned HTTP ' + statusCode,responseBody);
                logRecord.API_JSON_body__c = truncateText(requestBody);
                saveLogSafely(logRecord);
                return ('AML API error (' + statusCode + '): ' +truncateText(responseBody));
            }
    
            Map<String, Object> responseData;
            try {
                responseData =(Map<String, Object>) JSON.deserializeUntyped(responseBody);
            } catch (Exception jsonException) {
                logRecord.Status__c = 'Failed';
                logRecord.Status_Code__c =  String.valueOf(statusCode);
                logRecord.API_CalloutRequestBody__c = truncateText(requestBody);
                logRecord.API_CalloutResponseBody__c = truncateText(responseBody);
                logRecord.Error_Message__c = 'Unable to parse Solytics API response: ' + jsonException.getMessage();
                logRecord.Error_Stack_Trace__c = jsonException.getStackTraceString();
                logRecord.Error_Line_No__c =jsonException.getLineNumber();
                logRecord.Error_Type__c =jsonException.getTypeName();
               // logRecord.Error_Category__c ='JSON Parsing Error';
                saveLogSafely(logRecord);
                throw new AuraHandledException('Unable to parse the AML API response.');
            }

            // Extract the search ID.
            String searchId = responseData.containsKey('search_id') ? String.valueOf(responseData.get('search_id')): null;
            if (String.isBlank(searchId)) {
                logRecord.Status__c = 'Failed';
                logRecord.Status_Code__c = String.valueOf(statusCode);
                logRecord.API_CalloutRequestBody__c = truncateText(requestBody);
                logRecord.API_CalloutResponseBody__c =truncateText(responseBody);
                logRecord.Error_Message__c ='Successful HTTP response did not contain search_id.';
                //logRecord.Error_Category__c ='Invalid API Response';

                saveLogSafely(logRecord);
                throw new AuraHandledException('The API response did not contain search_id.');
            }
            if (objectType == 'Lead') {
                Lead leadToUpdate = new Lead(
                    Id = recordId,
                    Lead_Search_Id__c = searchId
                );

                update leadToUpdate;
            } else if (objectType == 'Account') {
                update new Account(
                    Id = recordId,
                    Account_Search_Id__c = searchId
                );
            } else if (objectType == 'Opportunity') {
                update new Opportunity(
                    Id = recordId,
                    Opportunity_Search_Id__c = searchId
                );
            }
           // IntegrationLogUtility.populateSuccess( logRecord,statusCode,requestBody, responseBody );
           // logRecord.API_JSON_body__c = truncateText(requestBody);
           // saveLogSafely(logRecord);
            return searchId;

        } catch (AuraHandledException e) {
            //validation/API messages.
            throw e;

        } catch (Exception e) {
            // Handles unexpected errors outside the HTTP callout. This creates a separate error log only if the error was not already handled by the callout sections.
            IntegrationLogUtility.captureError( CLASS_NAME,'submitScreening',e,null, DIRECTION );
            throw new AuraHandledException('AML screening failed: ' + e.getMessage() );
        }
    }

    private static Account getAccount(Id accountId) {
        return [SELECT Id, Name, Phone,Age__c, Date_Of_Birth__c, BillingStreet,BillingCity, BillingState,BillingPostalCode, BillingCountry FROM Account WHERE Id = :accountId LIMIT 1];
    }
     private static Map<String, Object> buildPayload(String name, String searchType,String email,String phone, String address, String city, String state,String zipcode,String country, String recordId, String age,String gender, String dateOfBirth ) {
        Map<String, Object> body = new Map<String, Object>();

        body.put('name', name);
        body.put('aliases', '');
        body.put('address', valueOrEmpty(address));
        body.put('zipcode', valueOrEmpty(zipcode));
        body.put('city', valueOrEmpty(city));
        body.put('state', valueOrEmpty(state));
        body.put('country', valueOrEmpty(country));
        body.put('country_of_jurisdiction', valueOrEmpty(country));

        body.put('applicant_id', '');
        body.put('application_id', '');
        body.put('sfdc_lead_id', recordId);

        body.put('branch_name', '');
        body.put('product_line', '');
        body.put('pennant_analyst_name', '');
        body.put('analyst_email_id', '');

        body.put('sanction_field', true);
        body.put('pep_field', true);
        body.put('ams_field', true);
        body.put('legal_field', false);
        body.put('corporate_field', false);
        body.put('risk_rating_field', true);
        body.put('deduplicate', false);
        body.put('target_date',Datetime.newInstance(Date.today().addDays(3),Time.newInstance(0, 0, 0, 0)).format('dd-MM-yy'));
        body.put('unique_id', 'sfdc_lead_id');

        body.put('target_date', '');
        body.put('other_fields', new Map<String, Object>{
                'field1' => '',
                'field2' => '',
                'field3' => ''
            }
        );

        body.put('screen_type', 'initial');
        body.put('search_type', searchType);

        body.put('age', age);
        body.put('gender', gender);
        body.put('date_of_birth', dateOfBirth);
        body.put('nationality', valueOrEmpty(country));
        body.put('email', valueOrEmpty(email));
       // body.put('nationality', 'country');
        body.put('national_id', '');
        body.put('team', '');
        body.put('voters_id', '');
        body.put('passport_number', '');
        body.put('pan', '');
        body.put('phone_number', valueOrEmpty(phone));
        body.put('ssn', '');
        body.put('tin', '');
        body.put('cin', '');
        body.put('drivers_license', '');
        body.put('headquarter', '');
        body.put('isin', '');
        body.put('gst', '');

        body.put('vessel_type', '');
        body.put('registered_owner', '');
        body.put('parent_company', '');
        body.put('imo', '');
        body.put('mmsi', '');
        body.put('flag_state', '');
        body.put('operator', '');
        body.put('manufacture_serial_number', '');
        body.put('construction_number', '');
        body.put('program', '');
        body.put('aircraft_model', '');
        body.put('income', '');

        return body;
    }

    private static String valueOrEmpty(String value) {
        return value == null ? '' : value;
    }

    private static String truncateText(String value) {
        if (value == null) {
            return null;
        }

        Integer maxLength = 131071;

        return value.length() > maxLength
            ? value.substring(0, maxLength)
            : value;
    }

    private static void saveLogSafely(Integration_Log__c logRecord) {
        System.debug('AML LOG SAVE START. Existing Id = ' + logRecord.Id);
        try {
            if (logRecord.Id == null) {
                insert logRecord;
            } else {
                update logRecord;
            }
            System.debug('AML LOG SAVE SUCCESS. Id = ' + logRecord.Id);

        } catch (DmlException e) {
            System.debug('AML LOG DML ERROR: ' + e.getMessage());
            for (Integer i = 0; i < e.getNumDml(); i++) {
                System.debug('DML Error ' + i +': ' + e.getDmlMessage(i) + '; Fields: ' + e.getDmlFields(i));
            }
            System.debug('DML Stack Trace: ' + e.getStackTraceString());

        } catch (Exception e) {
            System.debug('AML LOG SAVE ERROR: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
        }
    }

}