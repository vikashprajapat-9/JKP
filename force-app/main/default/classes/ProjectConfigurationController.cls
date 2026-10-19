public with sharing class ProjectConfigurationController {

    // Keeps one save well inside the DML and CPU limits
    private static final Integer MAX_ROWS = 50;
    // Starting Price is Currency(16, 2) and Square FT is Number(18, 0). The component sends numbers as JavaScript
    // doubles, which only carry 15 significant digits exactly, so the accepted ranges stay within that.
    private static final Decimal MAX_PRICE = Decimal.valueOf('10000000000000');
    private static final Decimal MAX_SQUARE_FT = Decimal.valueOf('1000000000000000');
    // Fields the component writes; Project is only set when a configuration is created
    private static final List<Schema.SObjectField> EDITABLE_FIELDS = new List<Schema.SObjectField>{
        Project_Configuration__c.Unit_Type__c,
        Project_Configuration__c.Starting_Price__c,
        Project_Configuration__c.Square_FT__c,
        Project_Configuration__c.Sub_Document__c
    };

    public class ConfigurationData {
        @AuraEnabled public Boolean canRead = false;
        @AuraEnabled public Boolean canCreate = false;
        @AuraEnabled public Boolean canEdit = false;
        @AuraEnabled public List<Option> unitTypes = new List<Option>();
        @AuraEnabled public List<Configuration> configurations = new List<Configuration>();
    }

    public class Option {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    public class Configuration {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String unitType;
        @AuraEnabled public Decimal startingPrice;
        @AuraEnabled public Decimal squareFt;
        @AuraEnabled public Id subDocumentId;
        @AuraEnabled public String fileName;
        @AuraEnabled public String fileUrl;
        // The configuration's own folder: <project> / Project Configurations / <this folder>
        @AuraEnabled public Id folderId;
        @AuraEnabled public String folderName;
        // False until SharePoint has created the folder (a few seconds after the configuration is saved)
        @AuraEnabled public Boolean folderReady = false;
    }

    public class FolderStatus {
        @AuraEnabled public Id configurationId;
        @AuraEnabled public Id folderId;
        @AuraEnabled public Boolean ready = false;
    }

    // What the component sends; only these values are written
    public class ConfigurationInput {
        @AuraEnabled public Id id { get; set; }
        @AuraEnabled public String unitType { get; set; }
        @AuraEnabled public Decimal startingPrice { get; set; }
        @AuraEnabled public Decimal squareFt { get; set; }
        // On an update: the file the user saw, and whether they removed it
        @AuraEnabled public Id subDocumentId { get; set; }
        @AuraEnabled public Boolean removeFile { get; set; }
    }

    // The project's configurations, the Unit Type values and what the running user is allowed to do.
    @AuraEnabled
    public static ConfigurationData getConfigurations(Id projectId) {
        requireProject(projectId);
        ConfigurationData data = new ConfigurationData();
        data.canRead = Project_Configuration__c.SObjectType.getDescribe().isAccessible();
        if (!data.canRead) {
            return data;
        }
        data.canCreate = canCreate();
        data.canEdit = canEdit();
        for (Schema.PicklistEntry entry : Project_Configuration__c.Unit_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                Option option = new Option();
                option.label = entry.getLabel();
                option.value = entry.getValue();
                data.unitTypes.add(option);
            }
        }
        data.configurations = queryConfigurations(projectId, null);
        return data;
    }

    // Creates all rows for the project in one go; nothing is saved if any row is invalid. Each new configuration
    // gets its own SharePoint folder (see ProjectConfigurationFolders); files are uploaded into it afterwards.
    // The result is in the same order as the rows that were sent.
    @AuraEnabled
    public static List<Configuration> createConfigurations(Id projectId, List<ConfigurationInput> configurations) {
        requireProject(projectId);
        if (!canCreate()) {
            throw userError('You do not have permission to add Project Configurations.');
        }
        if (configurations == null || configurations.isEmpty()) {
            throw userError('Add at least one configuration.');
        }
        if (configurations.size() > MAX_ROWS) {
            throw userError('You can add up to ' + MAX_ROWS + ' configurations at a time.');
        }

        Set<String> unitTypes = activeUnitTypes();
        List<Project_Configuration__c> records = new List<Project_Configuration__c>();
        for (Integer i = 0; i < configurations.size(); i++) {
            ConfigurationInput input = configurations[i];
            String rowLabel = 'Row ' + (i + 1) + ': ';
            if (input == null || input.id != null) {
                throw userError(rowLabel + 'This row cannot be added.');
            }
            if (input.subDocumentId != null) {
                throw userError(rowLabel + 'Files are uploaded after the configuration is saved.');
            }
            Project_Configuration__c record = new Project_Configuration__c(Project__c = projectId);
            applyInput(record, input, unitTypes, rowLabel, null);
            records.add(record);
        }
        save(records, true);

        Map<Id, Configuration> savedById = new Map<Id, Configuration>();
        for (Configuration config : queryConfigurations(projectId, new Map<Id, Project_Configuration__c>(records).keySet())) {
            savedById.put(config.id, config);
        }
        List<Configuration> result = new List<Configuration>();
        for (Project_Configuration__c record : records) {
            if (savedById.containsKey(record.Id)) {
                result.add(savedById.get(record.Id));
            }
        }
        return result;
    }

    // Saves the edited values of one configuration. Its file can be removed here; a new file is linked with
    // attachFile once it has been uploaded into the configuration's folder.
    @AuraEnabled
    public static Configuration updateConfiguration(Id projectId, ConfigurationInput configuration) {
        requireProject(projectId);
        if (!canEdit()) {
            throw userError('You do not have permission to edit Project Configurations.');
        }
        Project_Configuration__c existing = requireConfiguration(projectId, configuration == null ? null : configuration.id);

        Project_Configuration__c record = new Project_Configuration__c(Id = existing.Id);
        applyInput(record, configuration, activeUnitTypes(), '', existing.Unit_Type__c);
        // Only the file the user saw is removed; a file an upload linked in the meantime stays
        if (configuration.removeFile == true && existing.Sub_Document__c != null
                && existing.Sub_Document__c == configuration.subDocumentId) {
            record.Sub_Document__c = null;
        }
        save(new List<Project_Configuration__c>{ record }, false);
        return first(queryConfigurations(projectId, new Set<Id>{ record.Id }));
    }

    // Whether each configuration's SharePoint folder exists yet, so the component knows when it can upload.
    @AuraEnabled
    public static List<FolderStatus> getFolderStatus(Id projectId, List<Id> configurationIds) {
        requireProject(projectId);
        Set<Id> ids = new Set<Id>();
        for (Project_Configuration__c config : visibleConfigurations(projectId, configurationIds)) {
            ids.add(config.Id);
        }
        Map<Id, Document__c> folders = foldersByConfiguration(ids);
        List<FolderStatus> statuses = new List<FolderStatus>();
        for (Id configurationId : configurationIds) {
            if (!ids.contains(configurationId)) {
                continue;
            }
            FolderStatus status = new FolderStatus();
            status.configurationId = configurationId;
            Document__c folder = folders.get(configurationId);
            if (folder != null) {
                status.folderId = folder.Id;
                status.ready = String.isNotBlank(folder.Document_Id__c);
            }
            statuses.add(status);
        }
        return statuses;
    }

    // Creates the folder of a configuration that has none yet (for example one saved before folders existed, or
    // right after its project), and queues again a folder whose creation in SharePoint failed.
    @AuraEnabled
    public static FolderStatus requestFolder(Id projectId, Id configurationId) {
        requireProject(projectId);
        Project_Configuration__c existing = requireConfiguration(projectId, configurationId);
        ProjectConfigurationFolders.ensureFolders(new Set<Id>{ existing.Id });
        List<FolderStatus> statuses = getFolderStatus(projectId, new List<Id>{ existing.Id });
        return statuses.isEmpty() ? null : statuses[0];
    }

    // Links a file that was just uploaded into the configuration's own folder.
    @AuraEnabled
    public static Configuration attachFile(Id projectId, Id configurationId, Id subDocumentId) {
        requireProject(projectId);
        if (!canEdit()) {
            throw userError('You do not have permission to edit Project Configurations.');
        }
        Project_Configuration__c existing = requireConfiguration(projectId, configurationId);
        if (subDocumentId == null || subDocumentId.getSObjectType() != Sub_Document__c.SObjectType) {
            throw userError('The uploaded file is not valid. Please upload it again.');
        }
        Integer inFolder = [
            SELECT COUNT()
            FROM Sub_Document__c
            WHERE Id = :subDocumentId AND Document__r.Project_Configuration__c = :existing.Id
            WITH SYSTEM_MODE
        ];
        if (inFolder == 0) {
            throw userError('The uploaded file is not in this configuration\'s folder. Please upload it again.');
        }
        save(new List<Project_Configuration__c>{ new Project_Configuration__c(Id = existing.Id, Sub_Document__c = subDocumentId) }, false);
        return first(queryConfigurations(projectId, new Set<Id>{ existing.Id }));
    }

    private static void applyInput(Project_Configuration__c record, ConfigurationInput input, Set<String> unitTypes,
            String rowLabel, String storedUnitType) {
        String unitType = input.unitType == null ? '' : input.unitType.trim();
        if (String.isBlank(unitType)) {
            throw userError(rowLabel + 'Choose a unit type.');
        }
        // A value that was deactivated later can stay on the configurations that already have it
        Boolean unchanged = storedUnitType != null && unitType.equals(storedUnitType);
        if (!unchanged && !unitTypes.contains(unitType)) {
            throw userError(rowLabel + '"' + unitType + '" is not a valid unit type.');
        }
        Decimal price = input.startingPrice == null ? null : input.startingPrice.setScale(2, System.RoundingMode.HALF_UP);
        if (price != null && (price <= 0 || price >= MAX_PRICE)) {
            throw userError(rowLabel + 'Enter a starting price greater than zero, with at most 13 digits before the decimal point.');
        }
        if (input.squareFt != null && (input.squareFt <= 0 || input.squareFt >= MAX_SQUARE_FT
                || input.squareFt.stripTrailingZeros().scale() > 0)) {
            throw userError(rowLabel + 'Enter the square feet as a whole number greater than zero, with at most 15 digits.');
        }
        if (!unchanged) {
            record.Unit_Type__c = unitType;
        }
        record.Starting_Price__c = price;
        record.Square_FT__c = input.squareFt;
    }

    // Saves as the running user, so object and field permissions apply
    private static void save(List<Project_Configuration__c> records, Boolean isInsert) {
        try {
            if (isInsert) {
                Database.insert(records, AccessLevel.USER_MODE);
            } else {
                Database.update(records, AccessLevel.USER_MODE);
            }
        } catch (DmlException e) {
            // New rows are saved together, so the message says which row was refused (for example a unit type the
            // project already has)
            String rowLabel = isInsert ? 'Row ' + (e.getDmlIndex(0) + 1) + ': ' : '';
            throw userError(rowLabel + e.getDmlMessage(0));
        } catch (Exception e) {
            throw userError('The configurations could not be saved: ' + e.getMessage());
        }
    }

    // A configuration of this project that the running user can read
    private static Project_Configuration__c requireConfiguration(Id projectId, Id configurationId) {
        if (configurationId == null || configurationId.getSObjectType() != Project_Configuration__c.SObjectType) {
            throw userError('Choose a configuration of this project.');
        }
        List<Project_Configuration__c> found = visibleConfigurations(projectId, new List<Id>{ configurationId });
        if (found.isEmpty()) {
            throw userError('This configuration is not on this project any more. Refresh and try again.');
        }
        return found[0];
    }

    private static List<Project_Configuration__c> visibleConfigurations(Id projectId, List<Id> configurationIds) {
        if (configurationIds == null || configurationIds.isEmpty()) {
            return new List<Project_Configuration__c>();
        }
        try {
            return [
                SELECT Id, Project__c, Unit_Type__c, Sub_Document__c
                FROM Project_Configuration__c
                WHERE Id IN :configurationIds AND Project__c = :projectId
                WITH USER_MODE
            ];
        } catch (Exception e) {
            throw userError('You do not have access to Project Configurations. Ask your administrator for access.');
        }
    }

    private static List<Configuration> queryConfigurations(Id projectId, Set<Id> onlyIds) {
        List<Project_Configuration__c> records;
        try {
            records = onlyIds == null
                ? [
                    SELECT Id, Name, Unit_Type__c, Starting_Price__c, Square_FT__c, Sub_Document__c
                    FROM Project_Configuration__c
                    WHERE Project__c = :projectId
                    WITH USER_MODE
                    ORDER BY Unit_Type__c ASC NULLS LAST, Starting_Price__c ASC NULLS LAST, CreatedDate ASC
                    LIMIT 500
                ]
                : [
                    SELECT Id, Name, Unit_Type__c, Starting_Price__c, Square_FT__c, Sub_Document__c
                    FROM Project_Configuration__c
                    WHERE Project__c = :projectId AND Id IN :onlyIds
                    WITH USER_MODE
                    ORDER BY Unit_Type__c ASC NULLS LAST, Starting_Price__c ASC NULLS LAST, CreatedDate ASC
                ];
        } catch (Exception e) {
            throw userError('You do not have access to all Project Configuration fields. Ask your administrator for access.');
        }

        Set<Id> configurationIds = new Set<Id>();
        Set<Id> subDocumentIds = new Set<Id>();
        for (Project_Configuration__c record : records) {
            configurationIds.add(record.Id);
            if (record.Sub_Document__c != null) {
                subDocumentIds.add(record.Sub_Document__c);
            }
        }
        // File name and public SharePoint link, read the same way the SharePoint components read Sub Documents
        Map<Id, Sub_Document__c> subDocuments = subDocumentIds.isEmpty()
            ? new Map<Id, Sub_Document__c>()
            : new Map<Id, Sub_Document__c>([
                SELECT Id, Name, File_URL__c
                FROM Sub_Document__c
                WHERE Id IN :subDocumentIds
                WITH SYSTEM_MODE
            ]);
        Map<Id, Document__c> folders = foldersByConfiguration(configurationIds);

        List<Configuration> result = new List<Configuration>();
        for (Project_Configuration__c record : records) {
            Configuration config = new Configuration();
            config.id = record.Id;
            config.name = record.Name;
            config.unitType = record.Unit_Type__c;
            config.startingPrice = record.Starting_Price__c;
            config.squareFt = record.Square_FT__c;
            Sub_Document__c file = subDocuments.get(record.Sub_Document__c);
            if (file != null) {
                config.subDocumentId = file.Id;
                config.fileName = file.Name;
                config.fileUrl = file.File_URL__c;
            }
            Document__c folder = folders.get(record.Id);
            if (folder != null) {
                config.folderId = folder.Id;
                config.folderName = folder.Name;
                config.folderReady = String.isNotBlank(folder.Document_Id__c);
            }
            result.add(config);
        }
        return result;
    }

    // Each configuration's folder Document (the oldest one, should there ever be more)
    private static Map<Id, Document__c> foldersByConfiguration(Set<Id> configurationIds) {
        Map<Id, Document__c> folders = new Map<Id, Document__c>();
        if (configurationIds.isEmpty()) {
            return folders;
        }
        for (Document__c folder : [
            SELECT Id, Name, Document_Id__c, Project_Configuration__c
            FROM Document__c
            WHERE Project_Configuration__c IN :configurationIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ]) {
            if (!folders.containsKey(folder.Project_Configuration__c)) {
                folders.put(folder.Project_Configuration__c, folder);
            }
        }
        return folders;
    }

    private static Configuration first(List<Configuration> configurations) {
        return configurations.isEmpty() ? null : configurations[0];
    }

    private static Set<String> activeUnitTypes() {
        Set<String> values = new Set<String>();
        for (Schema.PicklistEntry entry : Project_Configuration__c.Unit_Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                values.add(entry.getValue());
            }
        }
        return values;
    }

    private static Boolean canCreate() {
        return Project_Configuration__c.SObjectType.getDescribe().isCreateable() && fieldsAllow(true);
    }

    private static Boolean canEdit() {
        return Project_Configuration__c.SObjectType.getDescribe().isUpdateable() && fieldsAllow(false);
    }

    private static Boolean fieldsAllow(Boolean forCreate) {
        List<Schema.SObjectField> fields = new List<Schema.SObjectField>(EDITABLE_FIELDS);
        if (forCreate) {
            fields.add(Project_Configuration__c.Project__c);
        }
        for (Schema.SObjectField field : fields) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (forCreate ? !describe.isCreateable() : !describe.isUpdateable()) {
                return false;
            }
        }
        return true;
    }

    private static void requireProject(Id projectId) {
        if (projectId == null || projectId.getSObjectType() != Project__c.SObjectType) {
            throw userError('Open a Project record to manage its configurations.');
        }
    }

    // AuraHandledException only exposes its text to Apex callers (and tests) when setMessage is also called
    private static AuraHandledException userError(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}