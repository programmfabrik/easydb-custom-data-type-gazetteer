# coding=utf8

import os
import json
import urllib.request, urllib.error, urllib.parse
import sys
from context import APIError, get_json_value
sys.path.append(os.path.abspath(os.path.dirname(__file__)) + '/../../easydb-library/src/python')
import noderunner


def get_string_from_baseconfig(db_cursor, class_str, key_str, parameter_str):
    return get_from_baseconfig(db_cursor, 'value_text', class_str, key_str, parameter_str)


def get_bool_from_baseconfig(db_cursor, class_str, key_str, parameter_str):
    return get_from_baseconfig(db_cursor, 'value_bool', class_str, key_str, parameter_str) == '1'


def get_from_baseconfig(db_cursor, value_column, class_str, key_str, parameter_str):
    if value_column not in ['value_text', 'value_int', 'value_bool']:
        return None

    try:
        db_cursor.execute("""
            SELECT %s
            FROM ez_base_config JOIN ez_value USING("ez_value:id")
            WHERE class = '%s'
            AND key = '%s'
            AND parameter = '%s'
        """ % ('%s%s' % (value_column, '::int' if value_column == 'value_bool' else ''),
               class_str, key_str, parameter_str))

        _result = db_cursor.fetchone()

        if not value_column in _result:
            return None

        if _result[value_column] is None:
            return None

        return str(_result[value_column])
    except:
        return None


def quote_value(value):
    return value.replace('\'', '\'\'')


def easydb_server_start(easydb_context):

    logger = easydb_context.get_logger('base.custom_data_type_gazetteer')

    easydb_context.register_callback('db_pre_update', {
        'callback': 'pre_update'
    })
    logger.info('registered callback for db_pre_update')


def pre_update(easydb_context, easydb_info):
    return GazetteerUpdate().update(easydb_context, easydb_info)


class GazetteerError(APIError):

    def __init__(self, type_str, description=None):
        super(GazetteerError, self).__init__('gazetteer_insert.' + type_str, description)


class GazetteerUpdate(object):

    def __init__(self):
        self.query_url = 'https://gazetteer.dainst.org/search.json'
        self.query_suffix = '&add=parents&noPolygons=1'
        self.place_url = 'https://gazetteer.dainst.org/place/'

    def update(self, easydb_context, easydb_info):

        self.logger = easydb_context.get_logger('base.custom_data_type_gazetteer')

        # get the object data
        data = get_json_value(easydb_info, 'data')
        if len(data) < 1:
            return []

        self.db_cursor = easydb_context.get_db_cursor()

        if not get_bool_from_baseconfig(self.db_cursor, 'system', 'gazetteer_plugin_settings', 'enabled'):
            self.logger.debug('automatic update not enabled')
            return data

        self.objecttype = get_string_from_baseconfig(self.db_cursor, 'system', 'gazetteer_plugin_settings', 'objecttype')
        if self.objecttype is None:
            self.logger.debug('automatic update enabled, but no objecttype selected')
            return data

        self.logger.debug('objecttype: %s' % self.objecttype)

        _dm = easydb_context.get_datamodel(
            show_easy_pool_link=True, show_is_hierarchical=True)
        self.objecttype_id = None
        self.easy_pool_link = None

        if not 'user' in _dm or not 'tables' in _dm['user']:
            self.logger.warn('invalid datamodel: user.tables not found')
            return data

        for _ot in _dm['user']['tables']:
            if 'name' in _ot and _ot['name'] == self.objecttype:
                if not ('is_hierarchical' in _ot and _ot['is_hierarchical'] == True):
                    raise GazetteerError('objecttype.not_hierarchical', 'objecttype: "%s"' % self.objecttype)

                self.easy_pool_link = 'easy_pool_link' in _ot and _ot['easy_pool_link'] == True
                try:
                    if 'table_id' in _ot:
                        self.objecttype_id = int(_ot['table_id'])
                        self.logger.debug('objecttype id: %s' % self.objecttype_id)
                except:
                    pass
                break

        if self.objecttype_id is None:
            self.logger.warn(
                'objecttype %s not found in datamodel' % self.objecttype)
            return data

        self.field_to = get_string_from_baseconfig(self.db_cursor, 'system', 'gazetteer_plugin_settings', 'field_to')
        if self.field_to is None:
            raise GazetteerError('field_to.not_set')

        if self.field_to.startswith(self.objecttype + "."):
            self.field_to = self.field_to[len(self.objecttype) + 1:]
        self.logger.debug('field_to: %s' % self.field_to)

        self.field_from = get_string_from_baseconfig(self.db_cursor, 'system', 'gazetteer_plugin_settings', 'field_from')
        if self.field_from is not None:
            if self.field_from.startswith(self.objecttype + "."):
                self.field_from = self.field_from[len(self.objecttype) + 1:]
            self.logger.debug('field_from: %s' % self.field_from)
        else:
            self.logger.debug('field_from not set, will use field_to %s' % self.field_to)

        self.script = "%s/../../build/scripts/gazetteer-update.js" % os.path.abspath(os.path.dirname(__file__))
        self.config = easydb_context.get_config()

        on_update = get_bool_from_baseconfig(self.db_cursor, 'system', 'gazetteer_plugin_settings', 'on_update')

        objects = []
        for i in range(len(data)):

            if not '_objecttype' in data[i]:
                self.logger.debug('could not find _objecttype in data[%s] -> skip' % i)
                objects.append(data[i])
                continue

            if data[i]['_objecttype'] != self.objecttype:
                self.logger.debug('data[%s]["_objecttype"] != %s -> skip' % (i, self.objecttype))
                objects.append(data[i])
                continue

            if not self.objecttype in data[i]:
                self.logger.debug('data[%s][%s] not found -> skip' % (i, self.objecttype))
                objects.append(data[i])
                continue

            if not on_update:
                if not '_version' in data[i][self.objecttype]:
                    self.logger.debug('on_update is enabled, but could not find _version in data[%s] -> skip' % i)
                    objects.append(data[i])
                    continue

                if data[i][self.objecttype]['_version'] != 1:
                    self.logger.debug('on_update is enabled, but _version of data[%s] = %s -> no insert -> skip'
                                      % (i, data[i][self.objecttype]['_version']))
                    objects.append(data[i])
                    continue

            _pool_id = None
            if self.easy_pool_link:
                _pool_id = get_json_value(data[i], '%s._pool.pool._id' % self.objecttype)
                if _pool_id is None:
                    self.logger.debug('could not find _pool.pool._id in data[%s] -> skip' % i)
                    objects.append(data[i])
                    continue
                self.logger.debug('pool id: %s' % _pool_id)

            _gazetteer_id = get_json_value(data[i], '%s.%s'
                                           % (self.objecttype, self.field_from)) if self.field_from is not None else None
            self.logger.debug('data.%s.%s.%s: \'%s\'' % (i, self.objecttype, self.field_from, _gazetteer_id))
            if _gazetteer_id is None:
                _gazetteer_id = get_json_value(data[i], '%s.%s.gazId' % (self.objecttype, self.field_to))
                self.logger.debug('data.%s.%s.%s.gazId: \'%s\'' % (i, self.objecttype, self.field_to, _gazetteer_id))
                if _gazetteer_id is None:
                    self.logger.debug('data.%s.%s.[%s / %s.gazId] not found or null -> skip'
                                      % (i, self.objecttype, self.field_from, self.field_to))
                    objects.append(data[i])
                    continue
            if _gazetteer_id is None or len(str(_gazetteer_id)) < 1:
                self.logger.debug('data.%s.%s.[%s / %s.gazId] not found or null -> skip'
                                  % (i, self.objecttype, self.field_from, self.field_to))
                objects.append(data[i])
                continue

            _response = self.load_gazetteer(easydb_context, _gazetteer_id)
            if _response is None:
                self.logger.warn('did not get a response from server for gazetteer id \'%s\'' % _gazetteer_id)
                return data

            _objects = []
            if 'gazId' in _response:
                _objects = [{
                    'id': 1,
                    'gazId': str(_response['gazId'])
                }]
            else:
                self.logger.warn('could not find \'gazId\' in response for query for gazetteer id %s' % _gazetteer_id)
                return data

            if 'parents' in _response:
                for p in range(len(_response['parents'])):
                    if 'gazId' in _response['parents'][p]:
                        _objects.append({
                            'id': p + 2,
                            'gazId': str(_response['parents'][p]['gazId'])
                        })

            _objects_to_index = set()

            _formatted_data = self.format_custom_data(_objects)
            if len(_formatted_data) < 1:
                self.logger.warn('did not get any formatted data from node_runner')
                return data

            _parent_id = None
            if len(_formatted_data) > 1:
                # do not export objects that exist
                _object_id, _, _gazetteer_id = self.exists_gazetteer_object(_formatted_data[0])
                if _object_id is not None:
                    self.logger.debug('object %s:%s already exists: %s' %
                                      (self.objecttype, _object_id, json.dumps(_formatted_data[0], indent=4)))
                    raise GazetteerError('object.duplicate', 'Gazetteer ID %s already exists in object %s (objecttype: %s)' %
                                         (_gazetteer_id, _object_id, self.objecttype))

                self.logger.debug('gazetteer object has %d parents' % (len(_formatted_data) - 1))
                k = len(_formatted_data) - 1
                while k >= 1:
                    _object_id, _owner_id, _gazetteer_id = self.exists_gazetteer_object(_formatted_data[k])
                    self.logger.debug('gazetteer object #%d: id %s (owner %s) | %s'
                                      % (k, str(_object_id), str(_owner_id), json.dumps(_formatted_data[k], indent=4)))

                    if _owner_id is None:
                        _owner_id = 1  # assume root user
                    if _object_id is None:
                        # object does not exist yet, create new object
                        _object_id = self.create_gazetteer_object(_formatted_data[k], _owner_id, _parent_id, _pool_id)
                        if _object_id is not None:
                            self.logger.debug('inserted new object %s:%s (parent: %s)' % (self.objecttype, _object_id, _parent_id))
                            _objects_to_index.add(_object_id)

                    # set parent id for the new object
                    _parent_id = _object_id
                    self.logger.debug('parent for new object: %s' % _parent_id)

                    k -= 1

            if len(_objects_to_index) > 0:
                easydb_context.update_user_objects(self.objecttype, list(_objects_to_index), True) # pass parameter to invalidate the object cache explicitly

            obj = data[i]
            obj[self.objecttype]['_id_parent'] = _parent_id
            obj[self.objecttype][self.field_to] = _formatted_data[0]
            self.logger.debug('data.%s.%s.%s updated with custom data from gazetteer repository'
                              % (i, self.objecttype, self.field_to))

            objects.append(obj)

        return objects

    def search_by_query(self, gazetteer_ids):
        _query = " OR ".join(gazetteer_ids)
        try:
            # XXX urllib2.quote() is not unicode compliant, https://bugs.python.org/msg88367
            _query_enc = urllib.parse.quote(_query.encode('utf-8'))

            _url = '%s?q=%s%s' % (
                self.query_url, _query_enc, self.query_suffix)
            self.logger.debug('load gazetteer data from %s' % _url)

            _response = urllib.request.urlopen(_url)
            _data = json.loads(_response.read())

            if 'result' in _data and isinstance(_data['result'], list):
                return _response.getcode(), _data['result']

            else:
                return _response.getcode(), str(_data)

        except Exception as e:
            self.logger.warn('could not get response for query \'%s\': %s' % (_query, str(e)))
            return 500, str(e)

    def load_gazetteer(self, easydb_context, gazetteer_id):
        _gaz_id = str(gazetteer_id)

        _statuscode, _response = self.search_by_query([_gaz_id])
        if _statuscode != 200:
            raise GazetteerError('repository.response_error', 'statuscode: %s, response: "%s"' % (_statuscode, str(_response)))
        if not isinstance(_response, list):
            raise GazetteerError('repository.response_error', 'statuscode: %s, response must be an array"' % _statuscode)

        if len(_response) > 0:
            return _response[0]

        return None


    def exists_gazetteer_object(self, gazetteer_data):

        if not 'gazId' in gazetteer_data:
            return None, None, None
        _gazetteer_id = gazetteer_data['gazId']

        try:
            statement = """
                SELECT "id:pkey", ":owner:ez_user:id"
                FROM %s
                WHERE %s::json ->> 'gazId' = '%s'
            """ % (self.objecttype, self.field_to, _gazetteer_id)
            self.logger.debug('[exists_gazetteer_object] SQL: %s' % statement)
            self.db_cursor.execute(statement)

            _result = self.db_cursor.fetchall()
            self.logger.debug('[exists_gazetteer_object] Result: %s' % json.dumps(_result, indent=4))
            if len(_result) < 1:
                return None, None, _gazetteer_id

            return int(_result[0]['id:pkey']), int(_result[0][':owner:ez_user:id']), _gazetteer_id
        except Exception as e:
            self.logger.warn('[exists_gazetteer_object] could not find exisiting objects in database: %s' % e.message)
            return None, None, _gazetteer_id

    def create_gazetteer_object(self, gazetteer_data, owner_id, parent_id=None, pool_id=None):
        try:
            _cols = []
            _values = []

            if parent_id is not None:
                _cols.append('"id:parent"')
                _values.append(str(parent_id))

            if pool_id is not None:
                _cols.append('"ez_pool:id"')
                _values.append(str(pool_id))

            _cols.append('":owner:ez_user:id"')
            _values.append(str(owner_id))

            _cols.append('"%s"' % self.field_to)
            _values.append('\'%s\'' % quote_value(json.dumps(gazetteer_data, indent=4)))

            self.db_cursor.execute("""
                INSERT INTO %s (%s)
                VALUES (%s)
                RETURNING "id:pkey"
                """ % (self.objecttype, ', '.join(_cols), ', '.join(_values)))

            _result = self.db_cursor.fetchone()
            if not 'id:pkey' in _result:
                raise GazetteerError('insert_error', 'could not find object id in result of INSERT')

            return int(_result['id:pkey'])
        except Exception as e:
            raise GazetteerError('database_error', str(e))

    def format_custom_data(self, gazetteer_data):

        _payload = {
            'action': 'update',
            'server_config': {},
            'plugin_config': {},
            'state': {},
            'batch_info': {
                'offset': 0,
                'total': len(gazetteer_data)
            },
            'objects': [
                {
                    'identifier': gazetteer_data[i]['id'],
                    'data': {
                        'gazId': gazetteer_data[i]['gazId']
                    }
                }
                for i in range(len(gazetteer_data))
            ]
        }

        out, err, exit_code = noderunner.call(self.config, self.script, json.dumps(_payload))

        if exit_code != 0:
            self.logger.warn(
                'could not get formatted gazetteer data from node_runner: %s' % str(err))
            return []

        try:
            content = json.loads(out)
            if not 'body' in content:
                raise Exception('\'body\' not in node_runner response')

            body = json.loads(content['body'])
            if not 'payload' in body:
                raise Exception('\'body.payload\' not in node_runner response')
            payload = body['payload']
            if not isinstance(payload, list):
                raise Exception('\'body.payload\' in node_runner response must be array')
            if len(payload) < 1:
                raise Exception('\'body.payload\' in node_runner response is empty')

            payload.sort(cmp=self.sort_by_identifier)

            return [p['data'] for p in payload if 'data' in p]

        except Exception as e:
            self.logger.warn(
                'could not format gazetteer data from node_runner response: %s' % str(e))
            return []


    def sort_by_identifier(self, a, b):
        return a['identifier'] - b['identifier']
