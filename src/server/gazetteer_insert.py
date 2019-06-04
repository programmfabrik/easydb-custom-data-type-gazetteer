# coding=utf8

import os
import json
import urllib2
import sys
import traceback
from datetime import datetime, date
from context import EasydbException, EasydbError, ServerError, get_json_value


def handle_exceptions(func):
    def func_wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except EasydbException as e:
            raise e
        except EasydbError as e:
            raise e
        except BaseException as e:
            exc_info = sys.exc_info()
            stack = traceback.extract_stack()
            tb = traceback.extract_tb(exc_info[2])
            full_tb = stack[:-1] + tb
            exc_line = traceback.format_exception_only(*exc_info[:2])
            traceback_info = '\n'.join([
                'Traceback (most recent call last)',
                ''.join(traceback.format_list(full_tb)),
                ''.join(exc_line)
            ])
            print (traceback_info)
            raise EasydbException('internal error', traceback_info)
    return func_wrapper


def get_string_from_baseconfig(db_cursor, class_str, key_str, parameter_str):
    return get_from_baseconfig(db_cursor, 'value_text', class_str, key_str, parameter_str)


def get_bool_from_baseconfig(db_cursor, class_str, key_str, parameter_str):
    return get_from_baseconfig(db_cursor, 'value_bool', class_str, key_str, parameter_str) == u'1'


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

        return unicode(_result[value_column])
    except:
        return None


@handle_exceptions
def easydb_server_start(easydb_context):

    logger = easydb_context.get_logger('base.custom_data_type_gazetteer')

    easydb_context.register_callback('db_pre_update', {
        'callback': 'pre_update'
    })
    logger.info('registered callback for db_pre_update')


def pre_update(easydb_context, easydb_info):
    return GazetteerUpdate().update(easydb_context, easydb_info)


class GazetteerError(ServerError):

    def __init__(self, type_str, description = None):
        super(GazetteerError, self).__init__('gazetteer_insert.' + type_str, description, None)


class GazetteerUpdate(object):


    def __init__(self):
        self.query_url = 'https://gazetteer.dainst.org/search.json'
        self.query_suffix = '&add=parents&noPolygons=1'
        self.place_url = 'https://gazetteer.dainst.org/place/'


    @handle_exceptions
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
            raise GazetteerError('objecttype.not_set')

        self.logger.debug('objecttype: %s' % self.objecttype)

        _dm = easydb_context.get_datamodel(show_easy_pool_link=True, show_is_hierarchical=True)
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

        self.gazetteer_cache = {}

        for i in range(len(data)):

            if not '_objecttype' in data[i]:
                self.logger.debug('could not find _objecttype in data[%s] -> skip' % i)
                continue

            if data[i]['_objecttype'] != self.objecttype:
                self.logger.debug('data[%s]["_objecttype"] != %s -> skip' % (i, self.objecttype))
                continue

            _pool_id = None
            if self.easy_pool_link:
                _pool_id = get_json_value(data[i], '%s._pool.pool._id' % self.objecttype)
                if _pool_id is None:
                    self.logger.debug('could not find _pool.pool._id in data[%s] -> skip' % i)
                    continue
                self.logger.debug('pool id: %s' % _pool_id)

            if not self.objecttype in data[i]:
                self.logger.debug('data[%s][%s] not found -> skip' % (i, self.objecttype))
                continue

            _gazetteer_id = get_json_value(data[i], '%s.%s' % (self.objecttype, self.field_from)) if self.field_from is not None else None
            self.logger.debug('data.%s.%s.%s: \'%s\'' % (i, self.objecttype, self.field_from, str(_gazetteer_id)))
            if _gazetteer_id is None:
                _gazetteer_id = get_json_value(data[i], '%s.%s.gazId' % (self.objecttype, self.field_to))
                self.logger.debug('data.%s.%s.%s.gazId: \'%s\'' % (i, self.objecttype, self.field_to, str(_gazetteer_id)))
                if _gazetteer_id is None:
                    self.logger.debug('data.%s.%s.[%s / %s.gazId] not found or null -> skip' % (i, self.objecttype, self.field_from, self.field_to))
                    continue

            _response, _parents = self.load_gazetteer(easydb_context, _gazetteer_id)
            _objects_to_index = set()

            _parent_id = None
            if _parents is not None:
                self.logger.debug('gazetteer object has %d parents' % len(_parents))
                k = len(_parents) - 1
                while k >= 0:
                    _object_id, _owner_id = self.exists_gazetteer_object(
                        _parents[k])
                    if _owner_id is None:
                        _owner_id = 1  # assume root user
                    if _object_id is None:
                        # object does not exist yet, create new object
                        _object_id = self.create_gazetteer_object(
                            _parents[k], _owner_id, _parent_id, _pool_id)
                        self.logger.debug('inserted new object %s:%s' % (self.objecttype, _object_id))
                        _objects_to_index.add(_object_id)
                    _parent_id = _object_id
                    self.logger.debug('parent id: %s' % _parent_id)
                    k -= 1

            easydb_context.update_user_objects(self.objecttype, list(_objects_to_index))

            data[i][self.objecttype]['_id_parent'] = _parent_id

            data[i]['_mask'] = '_all_fields'
            data[i][self.objecttype][self.field_to] = _response
            self.logger.debug('data.%s.%s.%s updated with custom data from gazetteer repository' % (i, self.objecttype, self.field_to))

        return data


    def search_by_query(self, gazetteer_ids):
        try:
            _query = " OR ".join(gazetteer_ids)

            _url = '%s?q=%s%s' % (
                self.query_url, urllib2.quote(_query), self.query_suffix)
            self.logger.debug('load gazetteer data from %s' % _url)

            _response = urllib2.urlopen(_url)
            _data = json.loads(_response.read())

            if 'result' in _data and isinstance(_data['result'], list):
                return _response.getcode(), _data['result']

            else:
                return _response.getcode(), str(_data[:128])

        except Exception as e:
            self.logger.warn('could not get response for query \'%s\': %s' % (_query, str(e)))
            return 500, str(e)


    def load_gazetteer(self, easydb_context, gazetteer_id):
        try:

            if not isinstance(gazetteer_id, unicode):
                _gaz_id = unicode(gazetteer_id)
            else:
                _gaz_id = gazetteer_id

            if _gaz_id in self.gazetteer_cache:
                self.logger.debug('return data for gazetteer id %s from cache' % _gaz_id)
                return self.gazetteer_cache[_gaz_id][0], self.gazetteer_cache[_gaz_id][1]

            _statuscode, _response = self.search_by_query([_gaz_id])
            if _statuscode != 200:
                raise GazetteerError('repository.response_error',
                    'statuscode: %d, response: "%s"' % (_statuscode, str(_response)))

            if len(_response) > 0:
                _data, _parents = self.format_custom_data(_response[0], True)

            self.gazetteer_cache[_gaz_id] = _data

            return _data, _parents

        except GazetteerError as e:
            raise e
        except:
            return None, None


    def exists_gazetteer_object(self, gazetteer_data):

        if not 'gazId' in gazetteer_data:
            return None, None
        _gazetteer_id = gazetteer_data['gazId']

        try:
            self.db_cursor.execute("""
                SELECT "id:pkey", ":owner:ez_user:id"
                FROM %s
                WHERE %s::json ->> 'gazId' = '%s'
            """ % (self.objecttype, self.field_to, _gazetteer_id))

            _result = self.db_cursor.fetchall()
            if len(_result) < 1:
                return None, None

            return int(_result[0]['id:pkey']), int(_result[0][':owner:ez_user:id'])
        except:
            return None, None


    def create_gazetteer_object(self, gazetteer_data, owner_id, parent_id=None, pool_id=None):
        try:
            _data = self.format_custom_data(gazetteer_data)
            if _data is None:
                return None

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
            _values.append('\'%s\'' % json.dumps(_data, indent=4))

            self.db_cursor.execute("""
                INSERT INTO %s (%s)
                VALUES (%s)
                RETURNING "id:pkey"
                """ % (self.objecttype, ', '.join(_cols), ', '.join(_values)))

            _result = self.db_cursor.fetchone()
            if not 'id:pkey' in _result:
                return None

            return int(_result['id:pkey'])
        except Exception as e:
            self.logger.warn("Could not create Gazetteer objects: %s", str(e))
            return None


    @handle_exceptions
    def insert_object_job(self, object_id):
        try:
            self.db_cursor.execute("""
                INSERT INTO ez_object_job (
                    type,
                    operation,
                    "ez_objecttype:id",
                    ez_object_id,
                    priority,
                    insert_time)
                VALUES (
                    'preindex',
                    'INSERT'::op_row,
                    %s,
                    %s,
                    -100,
                    NOW())
            """ % (self.objecttype_id, object_id))
            return True
        except:
            return False


    @handle_exceptions
    def format_custom_data(self, gazetteer_data, load_parents=False):

        for k in ['gazId', 'prefName']:
            if not k in gazetteer_data:
                return None

        _gaz_id = gazetteer_data['gazId']

        _custom_data = {
            'gazId': _gaz_id,
            'iconName': 'fa-map',
            '_fulltext': {
                'string': _gaz_id,
                'text': []
            },
            '_standard': {}
        }

        if 'title' in gazetteer_data['prefName']:
            _custom_data['displayName'] = gazetteer_data['prefName']['title']
            _custom_data['_standard']['text'] = gazetteer_data['prefName']['title']

        if 'names' in gazetteer_data:
            if isinstance(gazetteer_data['names'], list) and len(gazetteer_data['names']) > 0:
                _custom_data['otherNames'] = gazetteer_data['names']

                for n in gazetteer_data['names']:
                    if 'title' in n and not n['title'] in _custom_data['_fulltext']['text']:
                        _custom_data['_fulltext']['text'].append(n['title'])

        if 'types' in gazetteer_data:
            if isinstance(gazetteer_data['types'], list) and len(gazetteer_data['types']) > 0:
                _custom_data['types'] = gazetteer_data['types']

        if 'prefLocation' in gazetteer_data:
            if 'coordinates' in gazetteer_data['prefLocation']:
                if isinstance(gazetteer_data['prefLocation']['coordinates'], list) and len(gazetteer_data['prefLocation']['coordinates']) == 2:
                    _custom_data['position'] = {
                        'lng': gazetteer_data['prefLocation']['coordinates'][0],
                        'lat': gazetteer_data['prefLocation']['coordinates'][1]
                    }

        if not load_parents:
            return _custom_data

        _parents = None
        if 'parents' in gazetteer_data:
            _parents = gazetteer_data['parents']

        return _custom_data, _parents
