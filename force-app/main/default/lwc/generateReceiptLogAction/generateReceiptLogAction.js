import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class GenerateReceiptLogAction extends NavigationMixin(LightningElement) {
    @api invoke() {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Receipt_Log__c',
                actionName: 'new'
            }
        });
    }
}