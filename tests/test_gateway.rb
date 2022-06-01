require_relative "../gateway.rb"
require "test/unit"
require "digest"
require "cgi"

class TestGateway < Test::Unit::TestCase

    def setup
        @g = Gateway.new({}, '100856', 'pass', nil)
    end

    def test_fieldToHtml_single
      result = @g.fieldToHtml('anygivenkey', 'anygivenvalue')
      assert_equal('<input type="hidden" name="anygivenkey" value="anygivenvalue" />', result.strip())
    end

    def test_fieldToHtml_minimal
        simplierFields = {
            'name' => 'John',
            'age' => '42'
        }

        actual = @g.fieldToHtml('main', simplierFields)

        expected = '<input type="hidden" name="main[name]" value="John" />
        <input type="hidden" name="main[age]" value="42" />'

        assert_equal(expected.gsub(/\s/, ""), actual.gsub(/\s/, ""))
    end


    def test_fieldToHtml_nested
        fields = {
            'name' => 'John Smith',
            'age' => '42',
            'address' => {
                'street' => 'London Road',
                'town' => 'Bristol'
            }
        }

        actual = @g.fieldToHtml('main', fields)

        expected =
        '<input type="hidden" name="main[name]" value="John Smith" />
        <input type="hidden" name="main[age]" value="42" />
        <input type="hidden" name="main[address][street]" value="London Road" />
        <input type="hidden" name="main[address][town]" value="Bristol" />'


        assert_equal(expected.gsub(/\s/, ""), actual.gsub(/\s/, ""))
    end

    def test_simple
        assert_equal(4, 2 + 2 )
        result = @g.collectBrowserInfo({
           'HTTP_USER_AGENT' => '',
           'HTTP_ACCEPT' => '',
           'HTTP_ACCEPT_ENCODING' => '',
           'HTTP_ACCEPT_LANGUAGE' => '',
           'HTTP_ACCEPT_CHARSET'=> ''
      });

        assert_true(result.include?("browser"))
        assert_true(result.include?("1x1x1"))
  end

  def test_sign
    assert_match(/^86cdc/, @g.sign({'a' => 'one', 'b' => 'two'}))
    assert_match(/^cf50d/, @g.sign({'a' => 'one', 'b' => 'New lines! %0D %0D%0A'}))
    assert_match(/^7c952/, @g.sign({'a' => 'one', 'b' => 'strange "\'?& symbols '}))

    assert_match(/^666ec/, @g.sign({'key' => "Various new line characters \r\n \r \n \n\r"})) # 666ec matched PHP

  end

  def test_verify
    example = {'a' => 'one', 'b' => 'two', 'responseCode' => 'doesn\'t matter'};

    p 'Just about to sign'
    signature = @g.sign(example)
    p 'The resulting signature'
    p signature
    example['signature'] = signature

    assert_true(@g.verifyResponse(example));

    otherGateway = Gateway.new({}, '100856', 'other pass', nil)
    # We expect this to fail because the password is different
    assert_raise(RuntimeError) {
      otherGateway.verifyResponse(example)
    }

  end

  def test_simple_array_verify
    example = [['a', 'aKey'], ['b', 'bKey']]

    p 'Just about to sign'
    signature = @g.sign(example)
    p 'The resulting signature'
    p signature

    example.push(['signature', signature])

    assert_true(@g.verifyResponse(example));

  end


  def test_sign_3ds_response

    examplePMSHash = {
      'threeDSRef' => 'UDNLRVk6dHJhbnNhY3Rpb25JRD03OTYwOSZtZXJjaGFudElEPTEwMDg1NiZfX2xpZmVfXz0xNjA2Mzg4MTg1',
      'threeDSResponse[PaRes]' => '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',
      'threeDSResponse[MD]' => 'UDNLRVk6dHJhbnNhY3Rpb25JRD03OTYwOSZtZXJjaGFudElEPTEwMDg1NiZfX2xpZmVfXz0xNjA2Mzg4MTg1',
      'threeDSResponse[submit]' => 'Submit',
      'merchantID' => '100856'
      };

      examplePMS = [
        ['threeDSRef', 'UDNLRVk6dHJhbnNhY3Rpb25JRD03OTYwOSZtZXJjaGFudElEPTEwMDg1NiZfX2xpZmVfXz0xNjA2Mzg4MTg1'],
        ['threeDSResponse[PaRes]', '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'],
        ['threeDSResponse[MD]', 'UDNLRVk6dHJhbnNhY3Rpb25JRD03OTYwOSZtZXJjaGFudElEPTEwMDg1NiZfX2xpZmVfXz0xNjA2Mzg4MTg1'],
        ['threeDSResponse[submit]', 'Submit'],
        ['merchantID', '100856']
        ];

      exampleMPS = [
        ['threeDSRef', 'UDNLRVk6dHJhbnNhY3Rpb25JRD03OTYwOSZtZXJjaGFudElEPTEwMDg1NiZfX2xpZmVfXz0xNjA2Mzg4MTg1'],
        ['threeDSResponse[MD]', 'UDNLRVk6dHJhbnNhY3Rpb25JRD03OTYwOSZtZXJjaGFudElEPTEwMDg1NiZfX2xpZmVfXz0xNjA2Mzg4MTg1'],
        ['threeDSResponse[PaRes]', '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'],
        ['threeDSResponse[submit]', 'Submit'],
        ['merchantID', '100856']
      ];

    signaturePMS = @g.sign(examplePMS, 'Threeds2Test60System')
    signatureMPS = @g.sign(exampleMPS, 'Threeds2Test60System')

    assert_match(/^665fc/, signaturePMS) # PMS
    assert_match(/^b26602/, signatureMPS) #MPS


  end

  def test_shorter_sign_3ds_response

    exampleMPS = [
      ['threeDSRef', 'AAAAAAAAA'],
      ['threeDSResponse[MD]', 'MMMMMMMMM'],
      ['threeDSResponse[PaRes]', 'PPPPPPPPP'],
      ['threeDSResponse[submit]', 'Submit'],
      ['merchantID', '100856']
    ];

    examplePMS = [
      ['threeDSRef', 'AAAAAAAAA'],
      ['threeDSResponse[PaRes]', 'PPPPPPPPP'],
      ['threeDSResponse[MD]', 'MMMMMMMMM'],
      ['threeDSResponse[submit]', 'Submit'],
      ['merchantID', '100856']
      ];


    signatureMPS = @g.sign(exampleMPS, 'Threeds2Test60System')
    # signaturePMS = @g.sign(examplePMS, 'Threeds2Test60System')

    assert_match(/^b7700a/, signatureMPS) # MPS
    # assert_match(/^c8a5c/, signaturePMS) # PMS



  end

  def test_urlDecoding

  end

  def test_hostedForm
      # Show an example hosted form
  end
end