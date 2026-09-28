({
    afterRender: function (component, helper) {
        var afterRenderReturn = this.superAfterRender();
        if (helper && helper.adjustModalDimensions) {
            helper.adjustModalDimensions(component);
        }
        return afterRenderReturn;
    },

    rerender: function (component, helper) {
        var rerenderReturn = this.superRerender();
        if (helper && helper.adjustModalDimensions) {
            helper.adjustModalDimensions(component);
        }
        return rerenderReturn;
    }
})