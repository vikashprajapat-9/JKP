@isTest
private class partnerWebPortalProjectControllerTest {

    // A channel head (and an internal user) gets every active project with its location; the executive's limit is
    // tested with My Team (partnerWebPortalMyTeamControllerTest)
    @isTest
    static void listsTheActiveProjectsWithTheirLocation() {
        Project__c active = TestRecordDefaults.project('Victoria Golf Resort', true);
        active.Project_Location__Street__s = 'Vauxhall Street';
        active.Project_Location__City__s = 'Colombo';
        active.Project_Location__PostalCode__s = '00200';
        insert new List<Project__c>{ active, TestRecordDefaults.project('Old Tower', false) };

        List<partnerWebPortalProjectController.ProjectTile> tiles = partnerWebPortalProjectController.getProjects();

        System.assertEquals(1, tiles.size(), 'Only active projects: ' + tiles);
        System.assertEquals('Victoria Golf Resort', tiles[0].name);
        System.assertEquals('Vauxhall Street, Colombo, 00200', tiles[0].location, 'The parts the address has');
        System.assertEquals(1, partnerWebPortalProjectController.getMarketingProjects().size(), 'The same list');
    }
}