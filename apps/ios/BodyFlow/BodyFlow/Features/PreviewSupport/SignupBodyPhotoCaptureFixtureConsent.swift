#if DEBUG
import CryptoKit
import Foundation

/// Approved B5 content used only by the local DEBUG capture fixture.
/// No legal publication, backend document or Release fallback is provided.
enum SignupBodyPhotoCaptureFixtureConsent {
    static func document(for locale: String) -> SignupBodyPhotoConsent? {
        let body: String
        switch locale {
        case "pt-BR": body = portuguese
        case "en-US": body = english
        default: return nil
        }
        let digest = SHA256.hash(data: Data(body.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return SignupBodyPhotoConsent(
            documentKey: "body_photo_estimate_consent",
            version: "synthetic-b5-v2",
            locale: locale,
            body: body,
            bodyHash: digest,
            acceptedAt: nil
        )
    }

    // Exact UTF-8 SHA256: e45e4a38adbeab144430a9fd33df59d1754ecf154c7871d358cb0ad17762210d
    private static let portuguese = """
    Fotos do corpo para estimar o percentual de gordura

    Este passo é opcional e só para quem tem 18 anos ou mais. Você pode digitar seu percentual ou seguir sem informar, sem impedir a conclusão do cadastro.

    Envie três fotos do seu próprio corpo: frente, lado e costas, de roupa. Homens podem estar sem camisa, de shorts; mulheres, de top esportivo e shorts. Não envie fotos sem roupa nem de outra pessoa.

    A estimativa é visual e feita por inteligência artificial. Não é medida, exame ou diagnóstico, e não foi comparada com exame. O resultado chega sem revisão prévia de um profissional de saúde. Pode errar: as mesmas fotos podem dar números diferentes, e luz, roupa e posição podem mudar o resultado.

    Cada leitura produz um número estimado e pode gerar anotações sobre o corpo e a postura. Essas anotações ficam guardadas com o resultado da foto e não são mostradas a você. Quando a exclusão é concluída no app, o resultado da leitura é apagado do catálogo; a linha que registra a foto continua guardada.

    Quando as três fotos têm uma leitura utilizável, o número apresentado é a média aritmética das três leituras, com o mesmo peso para frente, lado e costas. Você vê a estimativa e as três leituras antes de decidir.

    Só ao confirmar expressamente a estimativa ela passa a ser o percentual usado na escolha do objetivo e no cálculo das metas, do mesmo jeito que um número digitado por você. Isso pode definir seu objetivo automaticamente. Mesmo sem confirmar, uma estimativa utilizável pode ficar guardada separadamente no perfil, identificada como estimativa das fotos e com a data. Guardar esse número não o aplica ao objetivo nem às metas.

    As fotos saem do celular e ficam em servidores de outra empresa, em área separada das fotos de refeição. Para a leitura, passam por um serviço que as encaminha ao fornecedor do modelo de inteligência artificial. Esses serviços podem estar fora do Brasil. O app não define quanto tempo essas empresas guardam isso nem se usam para treinar seus sistemas. A equipe do app e as ferramentas de inteligência artificial que ela usa podem ver o que fica guardado, inclusive estas fotos.

    Ao concluir o cadastro, o app solicita a exclusão das fotos deste passo, inclusive se estiverem incompletas ou se você recusar a estimativa. Se a exclusão não terminar, novas tentativas dependem de conexão e de você voltar ao app. Um envio já autorizado pode chegar depois de uma tentativa de exclusão. Por isso, não há garantia de que as fotos fiquem permanentemente ausentes, nem de exclusão das cópias dos serviços externos.

    Antes de concluir, você pode pedir a exclusão tocando em “Apagar fotos”. Se abandonar o cadastro sem concluir, não há limpeza automática garantida: as fotos podem continuar guardadas até você voltar e pedir a exclusão ou concluir. A original escolhida da galeria, e a cópia na nuvem da galeria, continuam lá; o app não as apaga.

    Apagar fotos não revoga este aceite nem apaga seu registro. Ele pode continuar válido para novos envios enquanto este texto estiver em vigor. Também não apaga automaticamente uma estimativa ou um percentual já registrado no perfil. Para pedir exclusão sem usar o app, escreva para contato@piperhub.com.br.

    Ao tocar em “Consentir e continuar”, você declara que tem 18 anos ou mais, que as fotos são suas, e autoriza o envio, a guarda e a leitura descritos aqui. Ao tocar em “Agora não”, você continua sem enviar fotos neste passo.
    """ + "\n"

    // Exact UTF-8 SHA256: a72cad69b3040007c81b38ab56b1b22bfc9b45c56a966e91b29bcaf45484b9e2
    private static let english = """
    Body photos to estimate body fat percentage

    This step is optional and only for people aged 18 or over. You can enter your percentage or continue without it, without preventing completion of sign-up.

    Send three photos of your own body: front, side and back, with clothing. Men may be shirtless and wear shorts; women may wear a sports top and shorts. Do not send nude photos or photos of anyone else.

    The estimate is visual and produced by artificial intelligence. It is not a measurement, examination or diagnosis, and has not been compared with an examination. You receive the result without prior review by a health professional. It can be wrong: the same photos can produce different numbers, and lighting, clothing and position can change the result.

    Each reading produces an estimated number and may generate notes about the body and posture. These notes are stored with the photo's result and are not shown to you. When deletion is completed in the app, the reading result is cleared from the catalogue; the record of the photo remains stored.

    When all three photos have a usable reading, the displayed number is the arithmetic mean of the three readings, with equal weight for front, side and back. You see the estimate and all three readings before deciding.

    Only when you explicitly confirm the estimate does it become the percentage used to choose your goal and calculate your targets, just as a number you enter would. This may set your goal automatically. Even without confirmation, a usable estimate may be stored separately in your profile, identified as a photo estimate and dated. Storing it does not apply it to your goal or targets.

    The photos leave your phone and are stored on another company's servers, separately from meal photos. For analysis, they pass through a service that forwards them to the artificial intelligence model provider. These services may be outside Brazil. The app does not determine how long these companies retain this content or whether they use it to train their systems. The app team and the artificial intelligence tools it uses can access stored content, including these photos.

    When you complete sign-up, the app requests deletion of the photos from this step, including incomplete photos or when you decline the estimate. If deletion does not finish, further attempts depend on a connection and on you returning to the app. An upload that was already authorised may arrive after a deletion attempt. There is therefore no guarantee that the photos remain permanently absent, or that copies held by external services are deleted.

    Before completing sign-up, you can request deletion by tapping “Delete photos”. If you leave sign-up without completing it, automatic cleanup is not guaranteed: photos may remain stored until you return to request deletion or complete sign-up. The original selected from your photo library, and its library cloud copy, remain there; the app does not delete them.

    Deleting photos does not revoke this consent or delete its record. It may remain valid for new uploads while this text is in force. It also does not automatically erase an estimate or percentage already stored in your profile. To request deletion without using the app, email contato@piperhub.com.br.

    By tapping “Consent and continue”, you declare that you are 18 or over, that the photos are yours, and authorise the transfer, storage and analysis described here. By tapping “Not now”, you continue without sending photos in this step.
    """ + "\n"

}
#endif
