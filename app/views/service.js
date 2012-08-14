// This is a temp view to get the router working
// remove later, testing basic routing in App

YUI.add("juju-view-service", function(Y) {

var views = Y.namespace("juju.views");
            

ServiceView = Y.Base.create('ServiceView', Y.View, [], {

    initializer: function () {
	console.log("View: Initialized: Service");
        var template_src = Y.one("#t-service").getHTML();
        this.template = Y.Handlebars.compile(template_src); 
    },

    render: function () {
        var container = this.get('container'),
            m = this.get('domain_models'),
            service = this.get("service"),
            units = m.units.get_units_for_service(service),
            width = 800,
            height = 600;

        var pack = d3.layout.pack()
            .sort(null)
            .size([width, height])
            .value(function(d) { return 1; })
            .padding(1.5);

        var svg = d3.select(container.getDOMNode()).append("svg")
        .attr("width", width)
        .attr("height", height);

        var node = svg.selectAll("rect")
            .data(pack.nodes({children: units}).slice(1))
            .enter().append("g")
            .attr("class", "unit")
            .attr("transform", function(d) {
                    return "translate(" + d.x + ", " + d.y + ")";});

        node.append("rect")
            .attr("class", "unit-border")
            .style("stroke", function(d) {
                       // XXX: add a class instead
                   return "black";
                   return {"running": "black"}[
                           d.get("agent-state")] || "red";
               })
            .attr("width", 100)
            .attr("height", 64)
            .style("fill", "#DA5616");
        console.log("View: Service: nodes", node);

        var unit_labels = node.append("text").append("tspan")
            .attr("class", "name")
            .attr("x", 4)
            .attr("y", "1em")
            .text(function(d) {
                      console.log("View: Service: label", d);
                      return d.get("id"); });
        

        return this;
    }
});

views.service = ServiceView;
}, "0.1.0", {
    requires: ['d3', 
               'base-build', 
               'handlebars', 
               'node', 
               "view", 
               "json-stringify"]
});
