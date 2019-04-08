var CustomDatatypeTest;

CustomDatatypeTest = (function () {

    class CustomDatatypeTest {

        constructor() { }

        log_error(what) {
            var error = {
                statuscode: 400,
                status: {

                    what: what
                }
            };
            console.log(JSON.stringify(error));
        }

        startup(config) {
            // TODO: do some checks, maybe check if the library server is reachable
            var ok = {
                statuscode: 200,
                "startup_ok": true
            }
            console.log(JSON.stringify(ok));
        }

        update_customdata(config, plugin, objs) {
            var updated_objects = [];

            for (var i = 0; i < objs.length; i++) {
                if (objs[i].identifier && objs[i].data) {
                    // TODO: check if data needs to be updated
                    if (i % 4 != 0)
                        continue;

                    var obj = objs[i];

                    obj.comment = "automatically updated by gazetteer plugin";

                    updated_objects.push(obj);
                }
            }

            var result = {
                statuscode: 200,
                "objects": updated_objects
            };
            console.log(JSON.stringify(result));
        }

        call() {
            var info = JSON.parse(process.argv[2]);

            if (!info.action) {
                this.log_error("key 'action' missing");
                return;
            }

            if (!info.config) {
                this.log_error("key 'config' missing");
                return;
            }

            if (info.action == "startup") {
                this.startup(info.config);
                return;
            }

            else if (info.action == "update") {
                if (!info.plugin) {
                    this.log_error("for update: key 'plugin' missing");
                    return;
                }
                if (!info.objects) {
                    this.log_error("for update: key 'objects' missing");
                    return;
                }
                if (!(info.objects instanceof Array)) {
                    this.log_error("for update: invalid key 'objects': must be array");
                    return;
                }
                // TODO: check validity of config, plugin (timeout), objects...

                this.update_customdata(info.config, info.plugin, info.objects);
                return;
            }

            else
                this.log_error("invalid action " + info.action);
        }
    }

    return CustomDatatypeTest;

})();

(function () {
    return new CustomDatatypeTest().call();
})();
