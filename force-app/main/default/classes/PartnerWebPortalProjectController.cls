public with sharing class PartnerWebPortalProjectController {

    public class ProjectTile {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public String location;
        @AuraEnabled public List<String> imageUrls;
    }

    // -----------------------------------------------------------
    // Shared tile builder — used by both Projects and Marketing
    // -----------------------------------------------------------
    @AuraEnabled(cacheable=true)
    public static List<ProjectTile> getProjects() {
        return buildTiles();
    }

    // Marketing tab reuses the same shape and source
    @AuraEnabled(cacheable=true)
    public static List<ProjectTile> getMarketingProjects() {
        return buildTiles();
    }

    private static List<ProjectTile> buildTiles() {
        List<ProjectTile> tiles = new List<ProjectTile>();

        List<Project__c> projects = [
            SELECT Id, Name, Project_Location__c
            FROM Project__c
            WHERE Active__c = true
            ORDER BY Name
            LIMIT 50
        ];

        String placeholderUrl = 'https://picsum.photos/400/250';

        for (Project__c p : projects) {
            ProjectTile tile = new ProjectTile();
            tile.id = p.Id;
            tile.name = p.Name;
            tile.location = buildLocationString(p.Project_Location__c);
            tile.imageUrls = new List<String>{ placeholderUrl };
            tiles.add(tile);
        }

        return tiles;
    }

    private static String buildLocationString(Address addr) {
        if (addr == null) return '';
        List<String> parts = new List<String>();
        if (String.isNotBlank(addr.getStreet()))     parts.add(addr.getStreet());
        if (String.isNotBlank(addr.getCity()))       parts.add(addr.getCity());
        if (String.isNotBlank(addr.getState()))      parts.add(addr.getState());
        if (String.isNotBlank(addr.getPostalCode())) parts.add(addr.getPostalCode());
        if (String.isNotBlank(addr.getCountry()))    parts.add(addr.getCountry());
        return String.join(parts, ', ');
    }
}