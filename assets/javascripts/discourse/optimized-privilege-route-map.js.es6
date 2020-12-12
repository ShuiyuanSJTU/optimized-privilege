export default function() {
  this.route("optimized-privilege", function() {
    this.route("actions", function() {
      this.route("show", { path: "/:id" });
    });
  });
};
