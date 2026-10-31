import unittest
from version import metadata, next_release

class ReleaseVersionTest(unittest.TestCase):
    def test_format(self):
        value = metadata({'date':'20261031','sequence':1})
        self.assertEqual(value['display'],'20261031(01)')
        self.assertEqual(value['build'],'20261031.1')
        self.assertEqual(value['tag'],'v20261031-01')
    def test_same_day_and_next_day(self):
        self.assertEqual(next_release({'date':'20261031','sequence':1},'20261031'),{'date':'20261031','sequence':2})
        self.assertEqual(next_release({'date':'20261031','sequence':99},'20261101'),{'date':'20261101','sequence':1})
    def test_invalid_or_backwards(self):
        for value in [{'date':'20260230','sequence':1},{'date':'20261031','sequence':0},{'date':'20261031','sequence':100}]:
            with self.assertRaises(ValueError): metadata(value)
        with self.assertRaises(ValueError): next_release({'date':'20261031','sequence':1},'20261030')
        with self.assertRaises(ValueError): next_release({'date':'20261031','sequence':99},'20261031')

if __name__ == '__main__': unittest.main()
