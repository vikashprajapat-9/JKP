import { LightningElement, api } from 'lwc';

export default class CustomSpinner extends LightningElement {
    @api message;
    @api spinnerText = 'Downloading, please wait...';
    @api secondText = 'Uploading to Google Drive....';
    connectedCallback() {
        debugger;
        setTimeout(() => {
            if(this.message != undefined){
                this.spinnerText = message
            }else{
                this.spinnerText = this.secondText;
            }
            
        }, 2000); 
    }
}